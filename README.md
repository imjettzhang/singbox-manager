# singbox-manager

一个用于管理 sing-box 节点的 Shell 脚本项目，支持节点添加、删除、配置查看、服务管理等功能，菜单交互友好，适合服务器一键部署和日常维护。

## 一键安装

```bash
wget https://gitea.rootde.com/imjettzhang/singbox-manager/src/branch/main/setup.sh -O setup.sh && chmod +x setup.sh && sudo ./setup.sh

```

安装完成后，可直接使用 `sb` 命令启动 singbox 管理脚本。

## 功能简介

- 一键安装/卸载 sing-box
- 多种协议节点管理（VLESS-REALITY、Shadowsocks、Hysteria2、TUIC、HTTP、SOCKS5）
- 节点增删查、配置文件备份与验证
- 服务状态查看与重启
- 交互式菜单，操作简单

## 说明

- 需 root 权限运行
- 依赖 jq、curl、systemctl 等常用工具
- 配置文件路径：`/etc/sing-box/config.json`
- 节点 URL 文件：`/etc/sing-box/node_url/nodes.json`
- 配置目录：`/etc/sing-box/`
- TLS 证书目录：`/etc/sing-box/tls/`
  - 证书文件命名格式：`domain-fullchain.cer`
  - 私钥文件命名格式：`domain-private.key`
- 系统服务文件：`/etc/systemd/system/sing-box.service`
- 管理脚本主程序：`singbox_manager.sh`（项目目录下）
- 快捷命令软链接：`/usr/local/bin/sb`
- 项目目录（源码）：`~/singbox-manager-main/`
- 安装脚本：`setup.sh`（项目目录下）
