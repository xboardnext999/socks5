#!/bin/bash

# 版本信息
VERSION="v1.0.1"

# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
plain='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${red}错误:${plain} 必须使用 root 用户运行！" && exit 1

# 环境安装与同步 (gost-s5 专用)
install_self() {
    # 强制跳过 GitHub 缓存获取最新版
    echo -e "${yellow}► 正在同步最新脚本 (v${VERSION})...${plain}"
    curl -Ls "https://raw.githubusercontent.com/xboardnext999/gost-s5/main/gost-s5.sh?v=$(date +%s)" -o /usr/local/bin/gost_s5_script
    chmod +x /usr/local/bin/gost_s5_script
    ln -sf /usr/local/bin/gost_s5_script /usr/local/bin/socks5
    ln -sf /usr/local/bin/gost_s5_script /usr/local/bin/sock5
    ln -sf /usr/local/bin/gost_s5_script /usr/local/bin/gost-s5
}

install_gost() {
    if [[ ! -f "/usr/bin/gost" ]]; then
        echo -e "${yellow}► 正在下载 GOST ...${plain}"
        ARCH=$(uname -m)
        URL="https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz"
        [[ "$ARCH" == "aarch64" ]] && URL="https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-armv8-2.11.5.gz"
        wget --no-check-certificate -qO gost.gz "$URL" && gunzip -f gost.gz && mv gost /usr/bin/gost && chmod +x /usr/bin/gost
    fi
}

gen_rand() { head /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-8} | head -n 1; }

# 使用系统原生 ss 命令探测端口
gen_port() {
    while :; do
        port=$((RANDOM % 50001 + 10000))
        (ss -tuln | grep -q ":$port ") || { echo "$port"; break; }
    done
}

get_ips() {
    IP4=$(curl -s4m 5 ip.sb || curl -s4m 5 ifconfig.me)
    IP6=$(curl -s6m 5 ip.sb || curl -s6m 5 ifconfig.me)
}

# 核心功能
add_proxy() {
    install_gost
    echo -e "--- 添加新代理端口 ---"
    read -p "请输入用户名 [随机]: " S_USER
    [[ -z "$S_USER" ]] && S_USER=$(gen_rand 6)
    read -p "请输入密码 [随机]: " S_PASS
    [[ -z "$S_PASS" ]] && S_PASS=$(gen_rand 12)
    read -p "请输入端口 [回车随机]: " S_PORT
    [[ -z "$S_PORT" ]] && S_PORT=$(gen_port)

    # 存储配置信息到/etc/gost-s5
    mkdir -p /etc/gost-s5
    echo "${S_USER}:${S_PASS}" > /etc/gost-s5/conf_${S_PORT}.txt

    cat <<EOF > /etc/systemd/system/gost_${S_PORT}.service
[Unit]
Description=Gost SOCKS5 Proxy Port ${S_PORT}
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/gost -L ${S_USER}:${S_PASS}@:${S_PORT}
Restart=always
RestartSec=5
MemoryLimit=60M

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable gost_${S_PORT} >/dev/null 2>&1
    systemctl restart gost_${S_PORT}
    echo -e "${green}✔ 配置成功！${plain}"
    show_single_info "$S_PORT" "$S_USER" "$S_PASS"
}

show_single_info() {
    local port=$1; local user=$2; local pass=$3; get_ips
    echo -e "${green}代理安装成功！已设置开机自启${plain}"
    echo -e "${yellow}您的Sock5详细信息，请务必保存好！${plain}"
    echo -e "IPV4: ${green}${IP4:-未探测到}${plain}"
    echo -e "IPV6: ${green}${IP6:-未探测到}${plain}"
    echo -e "用户: ${green}${user}${plain}"
    echo -e "密码: ${green}${pass}${plain}"
    echo -e "端口: ${green}${port}${plain}"
    echo -e "---"
    echo -e "${yellow}SOCKS5 详情：${plain}"
    [[ ! -z "$IP4" ]] && echo -e "IPv4 链接: ${cyan}socks5://${user}:${pass}@${IP4}:${port}${plain}"
    [[ ! -z "$IP6" ]] && echo -e "IPv6 链接: ${cyan}socks5://${user}:${pass}@[${IP6}]:${port}${plain}"
}

show_all_info() {
    services=$(ls /etc/systemd/system/gost_*.service 2>/dev/null)
    [[ -z "$services" ]] && echo "暂无代理信息" && return
    for s in $services; do
        port=$(echo $s | grep -oE '[0-9]+')
        auth=$(cat /etc/gost-s5/conf_${port}.txt 2>/dev/null)
        user=$(echo $auth | cut -d: -f1); pass=$(echo $auth | cut -d: -f2)
        echo "-----------------------------"
        show_single_info "$port" "$user" "$pass"
    done
}

manage_single() {
    echo -e "${yellow}当前端口列表：${plain}"
    ls /etc/systemd/system/gost_*.service 2>/dev/null | grep -oE '[0-9]+'
    read -p "请输入要操作的端口: " port
    [[ ! -f "/etc/systemd/system/gost_${port}.service" ]] && echo "端口不存在" && return
    echo "1. 启动 | 2. 停止 | 3. 重启 | 4. 删除"
    read -p "选择操作 [1-4]: " op
    case $op in
        1) systemctl start gost_$port && echo "已启动" ;;
        2) systemctl stop gost_$port && echo "已停止" ;;
        3) systemctl restart gost_$port && echo "已重启" ;;
        4) systemctl stop gost_$port; systemctl disable gost_$port; rm -f /etc/systemd/system/gost_$port.service /etc/gost-s5/conf_$port.txt; echo "已删除" ;;
    esac
}

batch_control() {
    echo "1. 全部开启 | 2. 全部停止 | 3. 全部重启"
    read -p "选择操作 [1-3]: " op
    for s in $(ls /etc/systemd/system/gost_*.service 2>/dev/null); do
        name=$(basename $s)
        [[ $op == 1 ]] && systemctl start $name
        [[ $op == 2 ]] && systemctl stop $name
        [[ $op == 3 ]] && systemctl restart $name
    done
    echo "批量操作完成"
}

show_status() {
    echo -e "------------------------------------------------"
    echo -e "端口\t\t状态\t\t内存占用"
    echo -e "------------------------------------------------"
    for s in $(ls /etc/systemd/system/gost_*.service 2>/dev/null); do
        port=$(echo $s | grep -oE '[0-9]+')
        status_raw=$(systemctl is-active gost_$port)
        if [[ "$status_raw" == "active" ]]; then
            status_show="${green}运行中${plain}"
        else
            status_show="${red}已停止${plain}"
        fi
        mem=$(systemctl show -p MemoryCurrent gost_$port | cut -d= -f2)
        if ! command -v bc &> /dev/null; then
            mem_mb="未知"
        else
            [[ "$mem" == "[not set]" || "$mem" == "0" ]] && mem_mb="0.00" || mem_mb=$(echo "scale=2; $mem/1024/1024" | bc)
        fi
        echo -e "${port}\t\t${status_show}\t\t${mem_mb}MB"
    done
    echo -e "------------------------------------------------"
}

uninstall_all() {
    echo -e "${yellow}► 正在彻底卸载 gost-s5 并清理残留...${plain}"
    services=$(ls /etc/systemd/system/gost_*.service 2>/dev/null)
    for s in $services; do
        name=$(basename $s)
        systemctl stop "$name" >/dev/null 2>&1
        systemctl disable "$name" >/dev/null 2>&1
    done
    pkill -9 gost >/dev/null 2>&1
    rm -rf /etc/systemd/system/gost_*.service /etc/gost-s5 /usr/bin/gost /usr/local/bin/socks5 /usr/local/bin/sock5 /usr/local/bin/gost-s5 /usr/local/bin/gost_s5_script
    systemctl daemon-reload
    echo -e "${green}✔ 卸载完成！系统已恢复干净。${plain}"
    exit 0
}

menu() {
    clear
    echo -e "${green} gost-s5 超轻量管理工具 ${yellow}${VERSION}${plain}"
    echo "-----------------------------"
    echo "1.安装/重置 SOCKS5 代理"
    echo "2.查看/管理单个端口 (启动/停止/删除)"
    echo "3.批量操作 (全部开启/全部停止/全部重启)"
    echo "4.查看当前运行状态"
    echo "5.查看所有代理信息"
    echo "6.卸载socks5服务"
    echo "7.退出菜单"
    echo "-----------------------------"
    read -rp "请输入选项 [1-7]: " num
    case $num in
        1) install_self; add_proxy ;;
        2) manage_single ;;
        3) batch_control ;;
        4) show_status ;;
        5) show_all_info ;;
        6) uninstall_all ;;
        7) exit 0 ;;
        *) echo -e "${red}无效选项${plain}" ;;
    esac
}

while true; do menu; read -p "按回车返回菜单..." ; done
