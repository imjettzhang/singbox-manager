
#!/bin/bash

# 将原来的 source ./common.sh 替换为如下内容：
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
source "$SCRIPT_DIR/common.sh"


#创建socks5节点配置
create_socks5_config() {
        # 生成用户名
    SOCKS5_USERNAME=$(sing-box generate rand 4 --hex)
    # 生成密码
    SOCKS5_PASSWORD=$(sing-box generate rand 4 --hex)
    # 生成节点标签 (节点类型+端口)
    NODE_TAG="socks5-$LISTEN_PORT"

    if [[ "$USE_AUTH" == "true" ]]; then
        # 有账号密码的配置
        SOCKS5_CONFIG=$(cat <<EOF
{
  "type": "socks",
  "tag": "$NODE_TAG",
  "listen": "::",
  "listen_port": $LISTEN_PORT,
  "users": [
    {
      "username": "$SOCKS5_USERNAME",
      "password": "$SOCKS5_PASSWORD"
    }
  ]
}
EOF
)
    else
        # 无账号密码的配置
        SOCKS5_CONFIG=$(cat <<EOF
{
  "type": "socks",
  "tag": "$NODE_TAG",
  "listen": "::",
  "listen_port": $LISTEN_PORT
}
EOF
)
    fi

    print_success "SOCKS5 代理节点配置已生成"
    echo "$SOCKS5_CONFIG"
}


show_socks5_node_info() {
    print_title "SOCKS5 代理节点信息"
    echo

    # 生成分享链接
    local formatted_address
    if [[ "$SERVER_ADDRESS" == *":"* ]]; then
        # IPv6 地址，保持方括号
        if [[ "$SERVER_ADDRESS" != "["* ]]; then
            formatted_address="[$SERVER_ADDRESS]"
        else
            formatted_address="$SERVER_ADDRESS"
        fi
    else
        # IPv4 地址直接使用
        formatted_address="$SERVER_ADDRESS"
    fi

    if [[ "$USE_AUTH" == "true" ]]; then
        SOCKS5_LINK="socks5://${SOCKS5_USERNAME}:${SOCKS5_PASSWORD}@${formatted_address}:${LISTEN_PORT}#${NODE_TAG}"
    else
        SOCKS5_LINK="socks5://${formatted_address}:${LISTEN_PORT}#${NODE_TAG}"
    fi

    print_info "SOCKS5 代理分享链接"
    echo -e "${GREEN}$SOCKS5_LINK${NC}"
    echo

    print_info "Clash 客户端配置示例:"
    # 格式化服务器地址（移除IPv6方括号）
    local clash_server="$SERVER_ADDRESS"
    if [[ $clash_server == "["*"]" ]]; then
        clash_server="${clash_server#[}"
        clash_server="${clash_server%]}"
    fi

    if [[ "$USE_AUTH" == "true" ]]; then
        cat << EOF
- name: $NODE_TAG
  type: socks5
  server: $clash_server
  port: $LISTEN_PORT
  username: $HTTP_USERNAME
  password: $HTTP_PASSWORD
EOF
    else
        cat << EOF
- name: $NODE_TAG
  type: socks5
  server: $clash_server
  port: $LISTEN_PORT
EOF
    fi
    echo
    print_warning "请注意放行端口${LISTEN_PORT}，否则无法连接"

    # 保存节点URL到 node_url.json
    NODE_URL_FILE="/etc/sing-box/node_url/nodes.json"
    if [ -n "$SOCKS5_LINK" ]; then
        tmp_url_file=$(mktemp)
        sudo jq --arg tag "$NODE_TAG" --arg url "$SOCKS5_LINK" '. + {($tag): $url}' "$NODE_URL_FILE" > "$tmp_url_file" && \
            sudo mv "$tmp_url_file" "$NODE_URL_FILE"
        print_success "节点URL已保存到: $NODE_URL_FILE"
    fi
}