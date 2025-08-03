#!/bin/bash

# 辅助输出函数
print_info() {
    echo -e "\033[36m[信息]\033[0m $1"
}
print_success() {
    echo -e "\033[32m[成功]\033[0m $1"
}
print_error() {
    echo -e "\033[31m[错误]\033[0m $1" >&2
}

print_warning() {
    echo -e "\033[33m[警告]\033[0m $1"
}

print_title() {
    echo -e "\033[34m=== $1 ===\033[0m"
}



# 启用 BBR
function enable_bbr() {
    print_info "正在检查是否已开启 BBR..."
    if lsmod | grep -q bbr && sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
        print_success "BBR 已启用！"
        return 0
    else
        print_error "未检测到 BBR，开始配置..."
    fi

    sudo tee -a /etc/sysctl.conf > /dev/null <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

    sudo sysctl -p

    if lsmod | grep -q bbr && sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
        print_success "BBR 已成功启用！"
    else
        print_error "BBR 启用失败，请检查内核版本是否 >= 4.9"
    fi
}


# 检查端口是否已被配置使用
check_port_in_config() {
    local port="$1"
    # 检查配置文件中是否已存在该端口
    if jq -e ".inbounds[] | select(.listen_port == $port)" "$CONFIG_FILE" >/dev/null 2>&1; then
        print_error "端口 '$port' 已被其他节点占用，请更换端口"
        return 1
    fi
    return 0
}



#选择SNI域名
select_sni() {
    print_title "选择SNI域名"
    echo "1) www.bing.com (默认)"
    echo "2) www.yahoo.com"
    echo "3) www.paypal.com"
    echo "4) aws.amazon.com"
    while true; do
        read -p "请选择SNI域名: " choice
        if [[ -z "$choice" ]]; then
            choice="1"
        fi
        case $choice in
            1)
                SNI_DOMAIN="www.bing.com"
                break
                ;;
            2)
                SNI_DOMAIN="www.yahoo.com"
                break
                ;;
            3)
                SNI_DOMAIN="www.paypal.com"
                break
                ;;
            4)
                SNI_DOMAIN="aws.amazon.com"
                break
                ;;
            *)
                print_error "无效选择，请输入 1-4"
                ;;
        esac
    done
    print_success "已选择SNI域名: $SNI_DOMAIN"
}


# 生成TLS证书
generate_tls_certificate() {
    local sni_domain="$1"
    
    print_info "生成 TLS 证书..."
    
    # TLS 证书目录
    TLS_DIR="/etc/sing-box/tls"
    if [ ! -d "$TLS_DIR" ]; then
        mkdir -p "$TLS_DIR"
    fi
    
    # 根据域名命名证书文件
    TLS_CERT="$TLS_DIR/${sni_domain}-fullchain.cer"
    TLS_KEY="$TLS_DIR/${sni_domain}-private.key"
    
    # 检查证书是否已存在
    if [[ -f "$TLS_CERT" && -f "$TLS_KEY" ]]; then
        print_warning "域名 $sni_domain 的TLS证书已存在"
        print_info "证书文件: $TLS_CERT"
        print_info "私钥文件: $TLS_KEY"
        read -p "是否覆盖现有证书？(Y/n,回车默认不覆盖): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "使用现有证书"
            return 0
        fi
        print_info "将覆盖现有证书"
    fi
    
    # 生成临时文件
    local temp_file=$(mktemp)
    
    # 使用 sing-box 生成证书
    if sing-box generate tls-keypair "$sni_domain" -m 456 > "$temp_file"; then
        # 提取私钥
        awk '/BEGIN PRIVATE KEY/,/END PRIVATE KEY/' "$temp_file" > "$TLS_KEY"
        # 提取证书
        awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' "$temp_file" > "$TLS_CERT"
        
        # 清理临时文件
        rm -f "$temp_file"
        
        # 设置权限
        chmod 600 "$TLS_KEY"
        chmod 644 "$TLS_CERT"
        
        print_success "TLS 证书生成成功"
        print_info "证书路径: $TLS_CERT"
        print_info "私钥路径: $TLS_KEY"
    else
        print_error "TLS 证书生成失败"
        rm -f "$temp_file"
        exit 1
    fi
}


#选择端口
select_port() {
    print_title "设置监听端口"
    echo "1) 随机端口（默认）"
    echo "2) 自定义端口"
    while true; do
        read -p "请选择端口设置方式: " mode
        if [[ -z "$mode" ]]; then
            mode="1"
        fi
        case $mode in
            1)
                # 随机分配端口
                local max_attempts=10
                local attempt=0
                while [ $attempt -lt $max_attempts ]; do
                    port=$((2000 + RANDOM % 58001))
                    if check_port_in_config "$port" && ! ss -tuln | grep -q ":$port "; then
                        LISTEN_PORT=$port
                        print_info "随机选择端口: $LISTEN_PORT"
                        break
                    fi
                    ((attempt++))
                done
                if [ -z "$LISTEN_PORT" ]; then
                    print_error "无法找到可用的随机端口，请选择自定义端口"
                    continue
                fi
                ;;
            2)
                while true; do
                    read -p "请输入端口号 (1-65535): " port
                    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
                        print_error "无效端口号，请输入1-65535之间的数字"
                        continue
                    fi
                    if ! check_port_in_config "$port"; then
                        local existing_tag=$(jq -r ".inbounds[] | select(.listen_port == $port) | .tag" "$CONFIG_FILE")
                        print_error "端口 $port 已被节点 '$existing_tag' 使用，请选择其他端口"
                        continue
                    fi
                    if ss -tuln | grep -q ":$port "; then
                        print_warning "端口 $port 可能已被系统其他服务占用，是否继续? (y/n): "
                        read -p "" confirm
                        if [[ $confirm =~ ^[Yy]$ ]]; then
                            LISTEN_PORT=$port
                            break
                        else
                            continue
                        fi
                    else
                        LISTEN_PORT=$port
                        break
                    fi
                done
                ;;
            *)
                print_error "无效选择，请输入 1 或 2"
                continue
                ;;
        esac
        break
    done
    print_success "设置端口: $LISTEN_PORT"
}

#获取本机IP地址
get_local_ip() {
    print_title "获取本机IP地址"
    echo "1) ifconfig.me (默认)"
    echo "2) icanhazip.com"
    echo "3) ident.me"

    while true; do
        read -p "请选择IP检测服务: " service_choice
        if [[ -z "$service_choice" ]]; then
            service_choice="1"
        fi
        case $service_choice in
            1)
                IP_SERVICE="ifconfig.me"
                SERVICE_URL="https://ifconfig.me"
                break
                ;;
            2)
                IP_SERVICE="icanhazip.com"
                SERVICE_URL="https://icanhazip.com"
                break
                ;;
            3)
                IP_SERVICE="ident.me"
                SERVICE_URL="https://ident.me"
                break
                ;;
            *)
                print_error "无效选择，请输入 1-3"
                ;;
        esac
    done

    print_success "已选择IP检测服务: $IP_SERVICE"
    print_info "正在获取公网IP地址..."

    IPV4=""
    IPV6=""

    if command -v curl >/dev/null 2>&1; then
        print_info "正在检测IPv4地址..."
        IPV4=$(curl -4 -s --connect-timeout 10 "$SERVICE_URL" 2>/dev/null | tr -d '\n\r ')
        if [[ $IPV4 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            print_success "$IP_SERVICE 检测到IPv4: $IPV4"
        else
            IPV4=""
            print_warning "$IP_SERVICE 获取IPv4失败"
        fi

        print_info "正在检测IPv6地址..."
        IPV6=$(curl -6 -s --connect-timeout 10 "$SERVICE_URL" 2>/dev/null | tr -d '\n\r ')
        if [[ $IPV6 =~ ^[0-9a-fA-F:]+$ ]] && [[ $IPV6 == *":"* ]]; then
            print_success "$IP_SERVICE 检测到IPv6: $IPV6"
        else
            IPV6=""
            print_warning "$IP_SERVICE 获取IPv6失败"
        fi
    fi

    # 构建选择列表
    options=()
    option_values=()
    option_count=1
    default_choice=""

    if [[ -n "$IPV4" ]]; then
        options+=("$option_count) IPv4: $IPV4 (默认)")
        option_values+=("$IPV4")
        default_choice="$option_count"
        ((option_count++))
    fi

    if [[ -n "$IPV6" ]]; then
        if [[ -z "$default_choice" ]]; then
            options+=("$option_count) IPv6: $IPV6 (默认)")
            default_choice="$option_count"
        else
            options+=("$option_count) IPv6: $IPV6")
        fi
        option_values+=("$IPV6")
        ((option_count++))
    fi

    options+=("$option_count) 手动输入IP地址或域名")

    if [[ ${#options[@]} -eq 1 ]]; then
        print_warning "未检测到公网IP地址"
        SERVER_ADDRESS=""
    elif [[ ${#options[@]} -eq 2 && -n "$default_choice" ]]; then
        index=$((default_choice - 1))
        PUBLIC_IP="${option_values[$index]}"
        SERVER_ADDRESS="$PUBLIC_IP"
        print_success "自动选择默认IP地址: $PUBLIC_IP"
    else
        print_warning "检测到多个IP地址:"
        for option in "${options[@]}"; do
            echo "$option"
        done

        while true; do
            if [[ -n "$default_choice" ]]; then
                read -p "请选择要使用的IP地址: " choice
            else
                read -p "请选择要使用的IP地址: " choice
            fi

            if [[ -z "$choice" && -n "$default_choice" ]]; then
                choice="$default_choice"
                print_info "使用默认选择: $choice"
            fi

            if [[ $choice =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le $option_count ]; then
                if [ "$choice" -eq $option_count ]; then
                    SERVER_ADDRESS=""
                    print_info "将手动输入IP地址或域名"
                    break
                else
                    index=$((choice - 1))
                    PUBLIC_IP="${option_values[$index]}"
                    SERVER_ADDRESS="$PUBLIC_IP"
                    print_success "已选择IP: $PUBLIC_IP"
                    break
                fi
            else
                print_error "无效选择，请输入 1-$option_count"
            fi
        done
    fi

    if [[ -z "$SERVER_ADDRESS" ]]; then
        # 询问用户手动输入IP或域名（不做格式验证，只要非空）
        while true; do
            echo "请输入服务器公网IP地址或域名（示例：192.168.1.1、2001:db8::1、example.com）："
            read -p "" server_input
            if [[ -n "$server_input" ]]; then
                SERVER_ADDRESS="$server_input"
                print_success "已设置服务器地址: $server_input"
                break
            else
                print_error "请输入有效的IP地址或域名"
            fi
        done
    fi

    if [[ $SERVER_ADDRESS == *":"* ]] && [[ $SERVER_ADDRESS != "["* ]]; then
        SERVER_ADDRESS="[$SERVER_ADDRESS]"
        print_info "检测到IPv6地址，已添加方括号: $SERVER_ADDRESS"
    fi

    print_success "设置服务器地址: $SERVER_ADDRESS"
}

#添加节点到配置文件
add_node_to_config() {
    local node_json="$1"
    if [[ -z "$node_json" || -z "$CONFIG_FILE" ]]; then
        echo "[错误] 参数缺失"
        return 1
    fi

    print_info "备份当前配置文件..."
    local backup_file="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG_FILE" "$backup_file" || { echo "[错误] 配置文件备份失败，终止操作"; return 1; }
    echo "[信息] 已备份配置文件: $backup_file"

    # 只保留最新10份备份，其他的删除
    local backup_pattern="${CONFIG_FILE}.backup.*"
    local backups=($(ls -1t $backup_pattern 2>/dev/null))
    if (( ${#backups[@]} > 10 )); then
        for old_backup in "${backups[@]:10}"; do
            rm -f "$old_backup"
        done
    fi

    if ! echo "$node_json" | jq . > /dev/null 2>&1; then
        echo "[错误] 传入的节点内容不是合法 JSON"
        return 1
    fi

    local new_tag
    new_tag=$(echo "$node_json" | jq -r '.tag')
    if jq -e --arg tag "$new_tag" '.inbounds[] | select(.tag == $tag)' "$CONFIG_FILE" > /dev/null; then
        echo "[错误] tag 已存在: $new_tag，未添加节点"
        return 1
    fi

    local tmp_json="/tmp/node_$$.json"
    local tmp_config="/tmp/config_$$.json"
    echo "$node_json" > "$tmp_json"

    if jq --slurpfile new_inbound "$tmp_json" '.inbounds += $new_inbound' "$CONFIG_FILE" > "$tmp_config"; then
        mv "$tmp_config" "$CONFIG_FILE"
        echo "[成功] 节点添加成功: $new_tag"
        rm -f "$tmp_json"
        return 0
    else
        echo "[错误] 节点添加失败，已保留备份: $backup_file"
        rm -f "$tmp_json" "$tmp_config"
        return 1
    fi
}

#验证配置文件
validate_config_json() {
    print_info "验证配置文件..."
    if sing-box check -c "$CONFIG_FILE"; then
        print_success "配置文件验证通过"
    else
        print_error "配置文件验证失败，正在恢复备份..."
        # 查找最新的备份文件
        latest_backup=$(ls -t "${CONFIG_FILE}.backup."* 2>/dev/null | head -1)
        if [ -n "$latest_backup" ]; then
            cp "$latest_backup" "$CONFIG_FILE"
            print_warning "已恢复到备份配置"
        fi
        exit 1
    fi
}

#重启sing-box服务
restart_singbox_service() {
    print_info "重启sing-box服务..."
    
    if systemctl restart sing-box; then
        print_success "服务重启成功"
        
        # 等待一下再检查状态
        sleep 2
        
        if systemctl is-active --quiet sing-box; then
            print_success "服务运行正常"
        else
            print_error "服务启动失败，请检查配置"
            systemctl status sing-box --no-pager -l
        fi
    else
        print_error "服务重启失败"
        exit 1
    fi
}


enable_singbox_autostart() {
    if systemctl list-unit-files | grep -q '^sing-box\.service'; then
        if sudo systemctl enable sing-box; then
            print_success "sing-box 已设置为开机自启。"
        else
            print_error "设置 sing-box 开机自启失败，请检查权限或服务状态。"
        fi
    else
        print_error "未检测到 sing-box 服务，请先安装 sing-box。"
    fi
}


# 选择是否启用认证
select_auth_mode() {
    echo
    print_title "选择认证模式"
    echo "1) 匿名访问"
    echo "2) 认证访问（默认）"
    echo
    
    while true; do
        read -p "请选择认证模式: " auth_choice
        case "$auth_choice" in
            1)
                USE_AUTH=false
                print_info "已选择: 匿名访问模式"
                break
                ;;
            ""|2)
                USE_AUTH=true
                print_info "已选择: 认证访问模式"
                break
                ;;
            *)
                print_error "无效选择，请输入 1 或 2"
                ;;
        esac
    done
}