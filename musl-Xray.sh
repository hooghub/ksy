#!/bin/sh
# =========================================
# Alpine 256MiB 容器专用
# 一键安装 Xray-core (musl)
# 生成 VLESS + 自签 TLS
# 默认端口 34469，可自选
# =========================================

CONFIG_DIR="/etc/xray"
CERT_DIR="$CONFIG_DIR/cert"
XRAY_BIN="/usr/local/bin/xray"

# 默认端口
DEFAULT_PORT=443

# 证书 / SNI 用的域名
DOMAIN="kyn.com"

# 客户端实际连接用的公网 IP（请改成你的真实 IP）
CONNECT_ADDR=$(curl -s ipv4.ip.sb || curl -s ifconfig.me || curl -s ipinfo.io/ip)

# 检查 root
if [ "$(id -u)" != "0" ]; then
    echo "请使用 root 执行"
    exit 1
fi

# 选择端口
echo "===================================="
echo "VLESS 端口设置"
read -p "请输入 VLESS 端口 [默认 ${DEFAULT_PORT}]： " VLESS_PORT

# 如果直接回车，使用默认端口
if [ -z "$VLESS_PORT" ]; then
    VLESS_PORT=$DEFAULT_PORT
fi

# 简单端口校验：必须是 1-65535 的数字
if ! echo "$VLESS_PORT" | grep -Eq '^[0-9]+$'; then
    echo "端口必须是数字，当前输入：$VLESS_PORT"
    exit 1
fi

if [ "$VLESS_PORT" -lt 1 ] || [ "$VLESS_PORT" -gt 65535 ]; then
    echo "端口必须在 1-65535 之间，当前输入：$VLESS_PORT"
    exit 1
fi

echo "使用端口：$VLESS_PORT"
echo "===================================="

# 创建目录
mkdir -p "$CONFIG_DIR" "$CERT_DIR"

# 安装依赖（补上 unzip）
apk update
apk add -q curl openssl jq tar unzip

# 生成自签 TLS（用域名 kyn.com）
echo "生成自签 TLS..."
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout "$CERT_DIR/server.key" -out "$CERT_DIR/server.crt" \
  -subj "/CN=$DOMAIN"

# 获取最新 Xray-core 版本
XRAY_VER=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
echo "最新 Xray-core 版本: $XRAY_VER"

# 下载 musl 版本 Xray-core
ASSET_NAME="Xray-linux-64.zip"  # Alpine 64位 musl版本可用
DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/$XRAY_VER/$ASSET_NAME"
echo "下载 Xray-core: $DOWNLOAD_URL"
curl -L -o /tmp/xray.zip "$DOWNLOAD_URL"
unzip -o /tmp/xray.zip -d /tmp/
mv /tmp/xray /usr/local/bin/xray
chmod +x /usr/local/bin/xray

# 生成 UUID
VLESS_UUID=$(cat /proc/sys/kernel/random/uuid)

# 生成配置文件（serverName 仍然是域名 kyn.com）
cat > "$CONFIG_DIR/config.json" <<EOF
{
  "log": { "loglevel": "info" },
  "inbounds": [
    {
      "port": $VLESS_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "$VLESS_UUID" }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "$DOMAIN",
          "certificates": [
            {
              "certificateFile": "$CERT_DIR/server.crt",
              "keyFile": "$CERT_DIR/server.key"
            }
          ]
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom" }
  ]
}
EOF

# 停止旧进程并启动 Xray
pkill xray 2>/dev/null || true
nohup /usr/local/bin/xray -config "$CONFIG_DIR/config.json" >/var/log/xray.log 2>&1 &

sleep 2

# 输出 VLESS URI
# 地址用公网 IP（CONNECT_ADDR），SNI 用域名 kyn.com
echo "========================="
echo "VLESS 节点 (公网 IP + 域名 SNI)："
echo "vless://$VLESS_UUID@$CONNECT_ADDR:$VLESS_PORT?encryption=none&security=tls&sni=$DOMAIN&allowInsecure=1#VLESS-xray"
echo "配置路径： $CONFIG_DIR/config.json"
echo "日志路径： /var/log/xray.log"
echo "========================="
echo "安装完成！"

