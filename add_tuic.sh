# 引入公共函数
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# TUIC专用函数
# 创建 TUIC 配置
create_tuic_config() {
    print_info "生成 TUIC 节点配置..."

    # 先生成TLS证书（设置TLS_CERT和TLS_KEY变量）
    generate_tls_certificate "$SNI_DOMAIN"

    # 生成 UUID 和密码
    TUIC_UUID=$(sing-box generate uuid)
    TUIC_PASSWORD=$(sing-box generate rand 16 --base64)

    # 创建节点标签 (节点类型+端口)
    NODE_TAG="tuic-$LISTEN_PORT"

    # 创建节点配置JSON，使用动态设置的证书路径
    TUIC_CONFIG=$(cat <<EOF
{
  "tag": "$NODE_TAG",
  "type": "tuic",
  "listen": "::",
  "listen_port": $LISTEN_PORT,
  "users": [
    {
      "uuid": "$TUIC_UUID",
      "password": "$TUIC_PASSWORD"
    }
  ],
  "congestion_control": "bbr",
  "tls": {
    "enabled": true,
    "alpn": [
      "h3"
    ],
    "server_name": "$SNI_DOMAIN",
    "certificate_path": "$TLS_CERT",
    "key_path": "$TLS_KEY"
  }
}
EOF
)

    print_success "TUIC 节点配置生成完成"
    echo "$TUIC_CONFIG"
}



show_tuic_node_info() {
    print_title "TUIC 节点信息"
    echo

    # 生成分享链接（请根据实际 TUIC 协议格式调整）

    TUIC_LINK="tuic://${TUIC_UUID}:${TUIC_PASSWORD}@${SERVER_ADDRESS}:${LISTEN_PORT}?congestion_control=bbr&alpn=h3&sni=${SNI_DOMAIN}&udp_relay_mode=native&allow_insecure=1#${NODE_TAG}"

    print_info "TUIC 分享链接"
    echo -e "${GREEN}$TUIC_LINK${NC}"
    echo

    print_info "Clash 客户端配置示例:"
    # 格式化服务器地址（移除IPv6方括号）
    local clash_server="$SERVER_ADDRESS"
    if [[ $clash_server == "["*"]" ]]; then
        clash_server="${clash_server#[}"
        clash_server="${clash_server%]}"
    fi

    cat << EOF
- name: $NODE_TAG
  type: tuic
  server: $clash_server
  port: $LISTEN_PORT
  uuid: $TUIC_UUID
  password: $TUIC_PASSWORD
  alpn: 
    - h3
  congestion-controller: bbr
  reduce-rtt: true
  heartbeat-interval: 10000ms
  skip-cert-verify: true
  sni: $SNI_DOMAIN
EOF
    echo
    print_warning "请注意放行端口${LISTEN_PORT}，否则无法连接"

    # 保存节点URL到 node_url.json
    NODE_URL_FILE="/etc/sing-box/node_url/nodes.json"
    if [ -n "$TUIC_LINK" ]; then
        tmp_url_file=$(mktemp)
        sudo jq --arg tag "$NODE_TAG" --arg url "$TUIC_LINK" '. + {($tag): $url}' "$NODE_URL_FILE" > "$tmp_url_file" && \
            sudo mv "$tmp_url_file" "$NODE_URL_FILE"
        print_success "节点URL已保存到: $NODE_URL_FILE"
    fi
}