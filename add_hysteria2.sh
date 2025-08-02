#!/bin/bash

# 引入公共函数
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Hysteria2专用函数



# 创建 Hysteria2 配置
create_hysteria2_config() {
    print_info "生成 Hysteria2 节点配置..."

    # 先生成TLS证书（设置TLS_CERT和TLS_KEY变量）
    generate_tls_certificate "$SNI_DOMAIN"

    # 生成密码
    HY2_PASSWORD=$(sing-box generate uuid)

    # 创建节点标签 (节点类型+端口)
    NODE_TAG="hysteria2-$LISTEN_PORT"

    # 创建Hysteria2节点配置JSON
    HY2_CONFIG=$(cat <<EOF
{
  "tag": "$NODE_TAG",
  "type": "hysteria2",
  "listen": "::",
  "listen_port": $LISTEN_PORT,
  "up_mbps": 100,
  "down_mbps": 100,
  "users": [
    {
      "password": "$HY2_PASSWORD"
    }
  ],
  "tls": {
    "enabled": true,
    "server_name": "$SNI_DOMAIN",
    "certificate_path": "$TLS_CERT",
    "key_path": "$TLS_KEY"
  }
}
EOF
)

    print_success "Hysteria2 节点配置生成完成"
    echo "$HY2_CONFIG"
}


#显示Hysteria2节点信息
show_hysteria2_node_info() {
    print_title "Hysteria2 节点信息"
    echo

    # 生成分享链接
    HY2_LINK="hysteria2://${HY2_PASSWORD}@${SERVER_ADDRESS}:${LISTEN_PORT}?alpn=h3&insecure=1&sni=${SNI_DOMAIN}#${NODE_TAG}"

    print_info "Hysteria2 分享链接"
    echo -e "${GREEN}$HY2_LINK${NC}"
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
  type: hysteria2
  server: $clash_server
  port: $LISTEN_PORT
  password: $HY2_PASSWORD
  alpn: 
    - h3
  up: 100
  down: 100
  skip-cert-verify: true
  sni: $SNI_DOMAIN
EOF
    echo
    print_warning "请注意放行端口${LISTEN_PORT}，否则无法连接"

    # 保存节点URL到 node_url.json
    NODE_URL_FILE="/etc/sing-box/node_url/nodes.json"
    if [ -n "$HY2_LINK" ]; then
        tmp_url_file=$(mktemp)
        sudo jq --arg tag "$NODE_TAG" --arg url "$HY2_LINK" '. + {($tag): $url}' "$NODE_URL_FILE" > "$tmp_url_file" && \
            sudo mv "$tmp_url_file" "$NODE_URL_FILE"
        print_success "节点URL已保存到: $NODE_URL_FILE"
    fi
}