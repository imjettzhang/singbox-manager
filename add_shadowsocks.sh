#!/bin/bash

# 将原来的 source ./common.sh 替换为如下内容：
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Shadowsocks专用函数
# 选择Shadowsocks加密方式
select_ss_method() {
    echo "请选择 Shadowsocks 加密方式："
    echo "1) 2022-blake3-aes-128-gcm (推荐)"
    echo "2) 2022-blake3-aes-256-gcm"
    echo "3) 2022-blake3-chacha20-poly1305"
    echo "4) aes-128-gcm"
    echo "5) aes-256-gcm"
    echo "6) chacha20-ietf-poly1305"
    echo
    
    while true; do
        read -p "请选择加密方式 (1-6，默认为 1): " method_choice
        
        if [ -z "$method_choice" ]; then
            method_choice=1
        fi
        
        case $method_choice in
            1)
                SS_METHOD="2022-blake3-aes-128-gcm"
                break
                ;;
            2)
                SS_METHOD="2022-blake3-aes-256-gcm"
                break
                ;;
            3)
                SS_METHOD="2022-blake3-chacha20-poly1305"
                break
                ;;
            4)
                SS_METHOD="aes-128-gcm"
                break
                ;;
            5)
                SS_METHOD="aes-256-gcm"
                break
                ;;
            6)
                SS_METHOD="chacha20-ietf-poly1305"
                break
                ;;
            *)
                print_error "无效选择，请输入 1-6"
                ;;
        esac
    done
    
    print_info "选择的加密方式: $SS_METHOD"
}

generate_ss_password() {
    # 根据加密方式确定密码生成方式
    if [[ "$SS_METHOD" == "2022-blake3-aes-128-gcm" ]]; then
        # 2022-blake3-aes-128-gcm 需要 16 字节 (128位) 密钥
        SS_PASSWORD=$(sing-box generate rand 16 --base64)
        print_info "生成的 2022-blake3-aes-128-gcm 密码: $SS_PASSWORD"
    elif [[ "$SS_METHOD" == "2022-blake3-aes-256-gcm" ]]; then
        # 2022-blake3-aes-256-gcm 需要 32 字节 (256位) 密钥
        SS_PASSWORD=$(sing-box generate rand 32 --base64)
        print_info "生成的 2022-blake3-aes-256-gcm 密码: $SS_PASSWORD"
    elif [[ "$SS_METHOD" == "2022-blake3-chacha20-poly1305" ]]; then
        # 2022-blake3-chacha20-poly1305 需要 32 字节 (256位) 密钥
        SS_PASSWORD=$(sing-box generate rand 32 --base64)
        print_info "生成的 2022-blake3-chacha20-poly1305 密码: $SS_PASSWORD"
    else
        # 传统方法使用随机字符串
        SS_PASSWORD=$(sing-box generate rand 16 --base64)
        print_info "生成的传统加密方式密码: $SS_PASSWORD"
    fi
}


# 创建Shadowsocks配置
create_shadowsocks_config() {
    print_info "生成Shadowsocks节点配置..."

    # 生成节点标签 (节点类型+端口)
    NODE_TAG="shadowsocks-$LISTEN_PORT"

    # 创建Shadowsocks节点配置JSON
    SS_CONFIG=$(cat <<EOF
{
  "tag": "$NODE_TAG",
  "type": "shadowsocks",
  "listen": "::",
  "listen_port": $LISTEN_PORT,
  "method": "$SS_METHOD",
  "password": "$SS_PASSWORD",
  "multiplex": {
    "enabled": false
  }
}
EOF
)

    print_success "Shadowsocks 节点配置生成完成"
    echo "$SS_CONFIG"
}

show_ss_node_info() {
    print_title "Shadowsocks 节点信息"
    echo

    # 生成Shadowsocks分享链接（SS URI 格式）
    # 格式: ss://BASE64-ENCODED-METHOD:PASSWORD@SERVER:PORT#TAG
    local base64_method_password
    base64_method_password=$(echo -n "${SS_METHOD}:${SS_PASSWORD}" | base64 -w 0)
    SS_LINK="ss://${base64_method_password}@${SERVER_ADDRESS}:${LISTEN_PORT}#${NODE_TAG}"

    print_info "Shadowsocks 分享链接"
    echo -e "$SS_LINK"
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
  type: ss
  server: $clash_server
  port: $LISTEN_PORT
  cipher: $SS_METHOD
  password: $SS_PASSWORD
  udp: true
EOF
    echo
    print_warning "请注意放行端口${LISTEN_PORT}，否则无法连接"

    # 保存节点URL到 node_url.json
    NODE_URL_FILE="/etc/sing-box/node_url/nodes.json"
    if [ -n "$SS_LINK" ]; then
        tmp_url_file=$(mktemp)
        sudo jq --arg tag "$NODE_TAG" --arg url "$SS_LINK" '. + {($tag): $url}' "$NODE_URL_FILE" > "$tmp_url_file" && \
            sudo mv "$tmp_url_file" "$NODE_URL_FILE"
        print_success "节点URL已保存到: $NODE_URL_FILE"
    fi
}


