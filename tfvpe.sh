check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "错误: 请以root用户身份运行此脚本"
        exit 1
    fi
}

confirm_installation() {
    read -p "您确定要开始安装节点吗? [y/n]: " choice
    case "$choice" in
        [yY])
            echo "安装继续"
            ;;
        [nN])
            echo "安装已取消"
            exit 0
            ;;
        *)
            echo "无效输入已退出脚本"
            exit 1
            ;;
    esac
}

install_dependencies() {
    echo "--> 正在检测依赖中..."
    local deps_required=("curl" "qrencode")
    local deps_to_install=()
    
    for dep in "${deps_required[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            deps_to_install+=("$dep")
        fi
    done

    if [ ${#deps_to_install[@]} -gt 0 ]; then
        echo "--> 将安装缺失的依赖: ${deps_to_install[*]}"
        apt-get update > /dev/null 2>&1
        apt-get install -y "${deps_to_install[@]}" > /dev/null 2>&1
        echo "--> 依赖安装完成"
    else
        echo "--> 所有依赖均已安装"
    fi
}

get_user_input() {
    clear
    echo "--- 节点安装程序 ---"
    SERVER_IP=$(curl -s ip.sb)
    UUID=$(cat /proc/sys/kernel/random/uuid)

    read -p "请输入监听端口 (默认 443): " LISTEN_PORT
    [ -z "${LISTEN_PORT}" ] && LISTEN_PORT="443"

    read -p "请输入伪装域名 (默认 www.microsoft.com): " REALITY_DEST
    [ -z "${REALITY_DEST}" ] && REALITY_DEST="www.microsoft.com"
}

install_xray_core() {
    echo "--> 正在安装Xray中..."
    bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) > /dev/null 2>&1
    
    echo "--> 正在生成Reality密钥中..."
    KEY_PAIR=$(/usr/local/bin/xray x25519)
    REALITY_PRIVATE_KEY=$(echo "$KEY_PAIR" | grep "Private key" | awk '{print $3}')
    REALITY_PUBLIC_KEY=$(echo "$KEY_PAIR" | grep "Public key" | awk '{print $3}')
    REALITY_SHORT_ID=$(openssl rand -hex 8)
}

configure_xray_reality() {
    echo "--> 正在写入配置文件..."
    local config_path="/usr/local/etc/xray/config.json"
    cat > $config_path <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${LISTEN_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "${UUID}","flow": "xtls-rprx-vision"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${REALITY_DEST}:443",
          "xver": 0,
          "serverNames": ["${REALITY_DEST}"],
          "privateKey": "${REALITY_PRIVATE_KEY}",
          "shortIds": ["${REALITY_SHORT_ID}"]
        }
      }
    }
  ],
  "outbounds": [{"protocol": "freedom"}]
}
EOF
}

start_services() {
    echo "--> 正在启动Xray服务..."
    systemctl enable xray > /dev/null 2>&1
    systemctl restart xray
    
    sleep 1
    if [ "$(systemctl is-active xray)" != "active" ]; then
        echo "错误: Xray启动失败, 请检查日志"
        journalctl -u xray --no-pager
        exit 1
    fi
}

display_results() {
    clear
    local share_link="vless://${UUID}@${SERVER_IP}:${LISTEN_PORT}?security=reality&sni=${REALITY_DEST}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp&flow=xtls-rprx-vision#Reality"

    echo "节点安装成功"
    echo "============================================================"
    echo " 地址: ${SERVER_IP}"
    echo " 端口: ${LISTEN_PORT}"
    echo " UUID: ${UUID}"
    echo " Flow: xtls-rprx-vision"
    echo " 安全: reality"
    echo " SNI: ${REALITY_DEST}"
    echo " 公钥: ${REALITY_PUBLIC_KEY}"
    echo " ShortID: ${REALITY_SHORT_ID}"
    echo "------------------------------------------------------------"
    echo "分享链接:"
    echo "${share_link}"
    echo ""
    echo "二维码 (可使用客户端扫描):"
    qrencode -t ANSIUTF8 "${share_link}"
    echo "============================================================"
}

main() {
    check_root
    confirm_installation
    install_dependencies
    get_user_input
    install_xray_core
    configure_xray_reality
    start_services
    display_results
}

main