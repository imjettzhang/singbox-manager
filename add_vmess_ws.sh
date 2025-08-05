#!/bin/bash

# 引入公共函数
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# VMESS WS专用函数

# 选择 WebSocket Host 和路径
select_ws_host_and_path() {
    echo "请选择 WebSocket Host："
    echo "1) www.bing.com (默认)"
    echo "2) www.heroku.com"
    echo "3) www.parler.com"
    echo "4) aws.amazon.com" 
    read -p "请选择 [1-4]: " ws_host_choice

    case "$ws_host_choice" in
        2) WS_HOST="www.heroku.com" ;;
        3) WS_HOST="www.parler.com" ;;
        4) WS_HOST="aws.amazon.com" ;;
        *) WS_HOST="www.bing.com" ;;
    esac

    # 生成随机路径
    WS_PATH="/$(sing-box generate rand 2 --hex)"
    echo "已生成随机 WebSocket 路径: $WS_PATH"
}

# 创建 VMESS TCP 节点配置
create_vmess_json() {
    print_info "生成节点配置..."

    # 生成UUID
    UUID=$(sing-box generate uuid)
    print_info "生成UUID: $UUID"

    NODE_TAG="vmess-${LISTEN_PORT}"

    VMESS_CONFIG=$(cat <<EOF
{
  "type": "vmess",
  "tag": "$NODE_TAG",
  "listen": "::",
  "listen_port": $LISTEN_PORT,
  "users": [
    {
      "name": "user",
      "uuid": "$UUID"
    }
  ],
  "transport": {
    "type": "ws",
    "path": "$WS_PATH",
    "headers": {
      "Host": "$WS_HOST"
    }
  }
}
EOF
)

    print_success "节点配置生成完成"
    echo "$VMESS_CONFIG"
}



# 显示 VMESS TCP 节点信息
show_vmess_node_info() {
    print_title "VMess 节点信息"
    echo

    # 构造 vmess 节点 JSON
    local vmess_json=$(cat <<EOF
{
  "v": "2",
  "ps": "$NODE_TAG",
  "add": "$SERVER_ADDRESS",
  "port": "$LISTEN_PORT",
  "id": "$UUID",
  "aid": "0",
  "net": "ws",
  "type": "none",
  "host": "$WS_HOST",
  "path": "$WS_PATH",
  "tls": ""
}
EOF
)
    # base64 编码
    local vmess_link="vmess://$(echo -n "$vmess_json" | base64 -w 0)"

    print_info "VMess 分享链接"
    echo -e "${GREEN}$vmess_link${NC}"
    echo
    print_warning "请注意放行端口${LISTEN_PORT}，否则无法连接"

    # 保存节点URL到 node_url.json
    NODE_URL_FILE="/etc/sing-box/node_url/nodes.json"
    if [ -n "$VLESS_LINK" ]; then
        tmp_url_file=$(mktemp)
        sudo jq --arg tag "$NODE_TAG" --arg url "$VLESS_LINK" '. + {($tag): $url}' "$NODE_URL_FILE" > "$tmp_url_file" && \
            sudo mv "$tmp_url_file" "$NODE_URL_FILE"
        print_success "节点URL已保存到: $NODE_URL_FILE"
    fi
}

# 主流程
add_vmess_tcp() {
    select_ws_host_and_path
    select_port
    get_local_ip
    create_vmess_json
    add_node_to_config
    validate_config_json
    restart_singbox_service
    show_vmess_node_info
    read -p "按回车返回..."
}

