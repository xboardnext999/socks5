#!/bin/bash

# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
plain='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${red}错误:${plain} 必须使用 root 用户运行！" && exit 1

# ==============================
# 基础安装与环境配置
# ==============================
install_self() {
    curl -Ls https://raw.githubusercontent.com/xboardnext999/socks5/main/socks5.sh -o /usr/local/bin/socks5_script
    chmod +x /usr/local/bin/socks5_script
    ln -sf /usr/local/bin/socks5_script /usr/local/bin/socks5
    ln -sf /usr/local/bin/socks5_script /usr/local/bin/sock5
}

install_gost() {
    if [[ ! -f "/usr/bin/gost" ]]; then
        echo -e "${yellow}► 正在下载 GOST 引擎...${plain}"
        ARCH=$(uname -m)
        URL="https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz"
        [[ "$ARCH" == "aarch64" ]] && URL="https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-armv8-2.11.5.gz"
        wget --no-check-certificate -qO gost.gz "$URL" && gunzip -f gost.gz && mv gost /usr/bin/gost && chmod +x /usr/bin/gost
    fi
}

gen_rand() { head /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-8} | head -n 1; }

# ==============================
# 多端口核心管理逻辑
# ==============================
add_proxy() {
    install_gost
    echo -e "--- 添加新代理端口 ---"
    read -p "请输入端口: " S_PORT
    [[ -z "$S_PORT" ]] && echo -e "${red}错误: 端口不能为空${plain}" && return
    if [[ -f "/etc/systemd/system/gost_${S_PORT}.service" ]]; then
        echo -e "${yellow}警告: 端口 ${S_PORT} 已存在，将覆盖配置${plain}"
    fi

    read -p "请输入用户名 [随机]: " S_USER
    [[ -z "$S_USER" ]] && S_USER=$(gen_rand 6)
    read -p "请输入密码 [随机]: " S_PASS
    [[ -z "$S_PASS" ]] && S_PASS=$(gen_rand 12)

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
    
    IP4=$(curl -s4m 5 ip.sb || curl -s4m 5 ifconfig.me)
    echo -e "${green}✔ 端口 ${S_PORT} 安装成功！${plain}"
    echo -e "链接: ${cyan}socks5://${S_USER}:${S_PASS}@${IP4}:${S_PORT}${plain}"
}

list_proxies() {
    echo -e "${yellow}当前已配置的代理列表：${plain}"
    services=$(ls /etc/systemd/system/gost_*.service 2>/dev/null)
    if [[ -z "$services" ]]; then echo "暂无代理"; return; fi
    
    printf "%-10s %-15s %-10s\n" "端口" "状态" "PID"
    for s in $services; do
        port=$(echo $s | grep -oE '[0-9]+')
        status=$(systemctl is-active gost_$port)
        pid=$(systemctl show -p MainPID gost_$port | cut -d= -f2)
        [[ "$status" == "active" ]] && status_col="${green}运行中${plain}" || status_col="${red}已停止${plain}"
        printf "%-10s %-25s %-10s\n" "$port" "$status_col" "$pid"
    done
}

manage_single() {
    list_proxies
    read -p "请输入要操作的端口: " port
    if [[ ! -f "/etc/systemd/system/gost_${port}.service" ]]; then echo "端口不存在"; return; fi
    echo "1. 启动 | 2. 停止 | 3. 重启 | 4. 删除"
    read -p "选择操作 [1-4]: " op
    case $op in
        1) systemctl start gost_$port ;;
        2) systemctl stop gost_$port ;;
        3) systemctl restart gost_$port ;;
        4) systemctl stop gost_$port; systemctl disable gost_$port; rm -f /etc/systemd/system/gost_$port.service; echo "已删除" ;;
    esac
}

batch_control() {
    echo "1. 全部启动 | 2. 全部停止 | 3. 全部重启"
    read -p "选择操作 [1-3]: " op
    services=$(ls /etc/systemd/system/gost_*.service 2>/dev/null)
    for s in $services; do
        name=$(basename $s)
        case $op in
            1) systemctl start $name ;;
            2) systemctl stop $name ;;
            3) systemctl restart $name ;;
        esac
    done
    echo -e "${green}批量操作完成${plain}"
}

uninstall_all() {
    echo -e "${yellow}► 正在清理所有代理...${plain}"
    pkill -9 gost
    rm -f /etc/systemd/system/gost_*.service
    rm -f /usr/bin/gost /usr/local/bin/socks5 /usr/local/bin/sock5 /usr/local/bin/socks5_script
    systemctl daemon-reload
    echo -e "${green}✔ 已彻底卸载${plain}"
}

# ==============================
# 菜单
# ==============================
menu() {
    clear
    echo -e "${green}=== SOCKS5 多端口管理工具 (200MB 内存优化版) ===${plain}"
    echo "-----------------------------"
    echo " 1. 添加新代理端口"
    echo " 2. 查看/管理单个端口 (启/停/删)"
    echo " 3. 批量控制 (全开/全停/全重)"
    echo " 4. 彻底卸载所有代理"
    echo " 5. 退出菜单"
    echo "-----------------------------"
    read -rp "请输入选项 [1-5]: " num
    case $num in
        1) install_self; add_proxy ;;
        2) manage_single ;;
        3) batch_control ;;
        4) uninstall_all ;;
        5) exit 0 ;;
        *) echo -e "${red}无效选项${plain}" ;;
    esac
}

while true; do menu; read -p "按回车返回菜单..." ; done
