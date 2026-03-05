#!/bin/bash

# 颜色定义
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${red}错误:${plain} 必须使用 root 用户运行！" && exit 1

# ==============================
# 自动安装 socks5 命令到系统
# ==============================
install_self() {
    if [[ ! -f "/usr/local/bin/socks5" ]]; then
        echo -e "${yellow}► 正在安装脚本至系统命令 (/usr/local/bin/socks5) ...${plain}"
        curl -Ls https://raw.githubusercontent.com/xboardnext999/socks5/main/socks5.sh -o /usr/local/bin/socks5
        chmod +x /usr/local/bin/socks5
        echo -e "${green}✔ 安装完成！以后可直接输入 [ socks5 ] 调出管理菜单${plain}"
    fi
}

# ==============================
# 随机生成函数
# ==============================
gen_rand() {
    head /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-8} | head -n 1
}

# ==============================
# 安装 GOST 主程序
# ==============================
install_gost() {
    if [[ -f "/usr/bin/gost" ]]; then
        echo -e "${green}✔ GOST 已存在，跳过下载${plain}"
        return
    fi
    echo -e "${yellow}► 正在下载轻量化代理引擎 (GOST)...${plain}"
    ARCH=$(uname -m)
    URL="https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz"
    [[ "$ARCH" == "aarch64" ]] && URL="https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-armv8-2.11.5.gz"
    
    wget --no-check-certificate -qO gost.gz "$URL"
    gunzip -f gost.gz
    mv gost /usr/bin/gost
    chmod +x /usr/bin/gost
}

# ==============================
# 配置并启动服务
# ==============================
setup_service() {
    echo -e "-----------------------------"
    echo -e "${yellow}设置 SOCKS5 信息（直接回车将随机生成）${plain}"
    
    read -p "请输入用户名 [随机]: " S_USER
    [[ -z "$S_USER" ]] && S_USER=$(gen_rand 6)
    
    read -p "请输入密码 [随机]: " S_PASS
    [[ -z "$S_PASS" ]] && S_PASS=$(gen_rand 12)
    
    read -p "请输入端口 [默认10000]: " S_PORT
    [[ -z "$S_PORT" ]] && S_PORT="10000"
    
    # 写入 Systemd (特别优化：限制内存占用，防止 200MB 机器死机)
    cat <<EOF > /etc/systemd/system/gost.service
[Unit]
Description=Gost SOCKS5 Proxy
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
    systemctl enable gost >/dev/null 2>&1
    systemctl restart gost

    # 获取公网 IP
    IP=$(curl -sS --connect-timeout 5 ip.sb || curl -sS --connect-timeout 5 ifconfig.me)

    echo -e "-----------------------------"
    echo -e "${green}✔ 代理安装成功！已设置开机自启${plain}"
    echo -e "${yellow}SOCKS5 详情：${plain}"
    echo -e "地址: ${green}${IP}${plain}"
    echo -e "端口: ${green}${S_PORT}${plain}"
    echo -e "用户: ${green}${S_USER}${plain}"
    echo -e "密码: ${green}${S_PASS}${plain}"
    echo -e "链接: ${cyan}socks5://${S_USER}:${S_PASS}@${IP}:${S_PORT}${plain}"
    echo -e "-----------------------------"
}

# ==============================
# 菜单系统
# ==============================
menu() {
    echo -e "${green}=== SOCKS5 一键工具 (适配小内存) ===${plain}"
    echo "-----------------------------"
    echo " 1. 安装 SOCKS5 代理"
    echo " 2. 查看当前运行状态"
    echo " 3. 卸载服务"
    echo " 4. 退出"
    echo "-----------------------------"
    read -rp "请输入选项 [1-4]: " num

    case $num in
        1) install_self; install_gost; setup_service ;;
        2) systemctl status gost ;;
        3) 
            systemctl stop gost && systemctl disable gost
            rm -f /etc/systemd/system/gost.service /usr/bin/gost /usr/local/bin/socks5
            echo -e "${green}✔ 卸载完成，所有文件已清理${plain}" 
            ;;
        4) exit 0 ;;
        *) echo -e "${red}无效选项${plain}" ;;
    esac
}

menu
