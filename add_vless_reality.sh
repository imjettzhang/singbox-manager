#!/bin/bash

# 引入公共函数
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# VLESS Reality专用函数



# 生成Reality密钥对
generate_reality_keypair() {
    print_info "生成Reality密钥对..."
    local keypair=$(sing-box generate reality-keypair)
    
    # 解析私钥和公钥
    PRIVATE_KEY=$(echo "$keypair" | grep "PrivateKey:" | awk '{print $2}')
    PUBLIC_KEY=$(echo "$keypair" | grep "PublicKey:" | awk '{print $2}')
    
    if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
        print_error "生成密钥对失败"
        exit 1
    fi
    
    print_success "密钥对生成成功"
    print_info "私钥: $PRIVATE_KEY"
    print_info "公钥: $PUBLIC_KEY"
}



create_vless_json() {
    print_info "生成节点配置..."

    # 生成UUID
    UUID=$(sing-box generate uuid)
    print_info "生成UUID: $UUID"

    # 生成密钥对
    generate_reality_keypair

    # 创建节点标签 (节点类型+端口)
    NODE_TAG="vless-reality-$LISTEN_PORT"

    # 创建节点配置JSON
    VLESS_CONFIG=$(cat <<EOF
{
  "tag": "$NODE_TAG",
  "type": "vless",
  "listen": "::",
  "listen_port": $LISTEN_PORT,
  "users": [
    {
      "uuid": "$UUID",
      "flow": "xtls-rprx-vision"
    }
  ],
  "tls": {
    "enabled": true,
    "server_name": "$SNI_DOMAIN",
    "reality": {
      "enabled": true,
      "handshake": {
        "server": "$SNI_DOMAIN",
        "server_port": 443
      },
      "private_key": "$PRIVATE_KEY",
      "short_id": [""]
    }
  }
}

EOF
)

    print_success "节点配置生成完成"
    echo "$VLESS_CONFIG"
}




show_vless_node_info()  {
    print_title "VLESS-REALITY 节点信息"
    echo
    
    # 生成VLESS分享链接
    VLESS_LINK="vless://${UUID}@${SERVER_ADDRESS}:${LISTEN_PORT}?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp&sni=${SNI_DOMAIN}&pbk=${PUBLIC_KEY}&fp=chrome#vless-reality-${LISTEN_PORT}"
    
    print_info "VLESS 分享链接"
    echo -e "${GREEN}$VLESS_LINK${NC}"
    echo
    print_info "Clash客户端配置:"
    
    # 格式化服务器地址（移除IPv6方括号）
    local clash_server="$SERVER_ADDRESS"
    if [[ $clash_server == "["*"]" ]]; then
        clash_server="${clash_server#[}"
        clash_server="${clash_server%]}"
    fi
    
    cat << EOF
- name: $NODE_TAG
  type: vless
  server: $clash_server
  port: $LISTEN_PORT
  uuid: $UUID
  tls: true
  client-fingerprint: chrome
  servername: $SNI_DOMAIN
  network: tcp
  reality-opts:
    public-key: $PUBLIC_KEY
    short-id: ""
  tfo: false
  skip-cert-verify: false
  flow: xtls-rprx-vision
EOF
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
add_vless_reality() {
    select_sni
    select_port
    get_local_ip
    create_vless_json
    add_node_to_config
    validate_config_json
    restart_singbox_service
    show_vless_node_info
    read -p "按回车返回..."
}

