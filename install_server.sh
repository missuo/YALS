#!/bin/bash
# install_server.sh - YALS Server Installer / Updater (GitHub Release Version)

set -e

REPO="missuo/YALS"

SERVER_DIR="/etc/yals"
SERVER_BIN="/usr/bin/yals_server"
CONFIG_FILE="$SERVER_DIR/config.yaml"
SERVICE_FILE="/etc/systemd/system/yals.service"
WEB_DIR="$SERVER_DIR/web"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

command -v curl >/dev/null 2>&1 || { echo -e "${RED}[ERROR]${NC} curl is not installed"; exit 1; }
command -v unzip >/dev/null 2>&1 || { echo -e "${RED}[ERROR]${NC} unzip is not installed"; exit 1; }
command -v systemctl >/dev/null 2>&1 || { echo -e "${RED}[ERROR]${NC} systemd is not supported"; exit 1; }

# Detect system architecture
detect_arch() {
  local arch=$(uname -m)
  case "$arch" in
    x86_64|amd64)
      echo "amd64"
      ;;
    aarch64|arm64)
      echo "arm64"
      ;;
    *)
      echo -e "${RED}[ERROR]${NC} Unsupported architecture: $arch"
      exit 1
      ;;
  esac
}

# Detect OS
detect_os() {
  local os=$(uname -s | tr '[:upper:]' '[:lower:]')
  case "$os" in
    linux)
      echo "linux"
      ;;
    darwin)
      echo "darwin"
      ;;
    *)
      echo -e "${RED}[ERROR]${NC} Unsupported OS: $os"
      exit 1
      ;;
  esac
}

# Get latest release download URL for the specific architecture
get_latest_download_url() {
  local os=$(detect_os)
  local arch=$(detect_arch)
  local asset_pattern="yals_.*_${os}_${arch}.zip"
  
  curl -s "https://api.github.com/repos/$REPO/releases/latest" \
    | grep "browser_download_url" \
    | grep -E "$asset_pattern" \
    | head -n 1 \
    | cut -d '"' -f 4
}

# ========== Update Mode ==========
if [[ "$1" == "update" ]]; then
  echo -e "${CYAN}========== YALS SERVER Update Mode ==========${NC}"

  DOWNLOAD_URL=$(get_latest_download_url)
  if [[ -z "$DOWNLOAD_URL" ]]; then
    echo -e "${RED}[ERROR]${NC} Failed to get download URL from GitHub Release"
    exit 1
  fi

  echo -e "${YELLOW}[INFO]${NC} Downloading latest server: $DOWNLOAD_URL"
  curl -L -o "/tmp/yals_server.zip" "$DOWNLOAD_URL"
  
  echo -e "${YELLOW}[INFO]${NC} Extracting..."
  unzip -o -j "/tmp/yals_server.zip" "*/yals_server" -d "/tmp/"
  chmod +x "/tmp/yals_server"
  mv "/tmp/yals_server" "$SERVER_BIN"
  
  # Also update web files
  echo -e "${YELLOW}[INFO]${NC} Updating web files..."
  rm -rf "$WEB_DIR"
  mkdir -p "$WEB_DIR"
  unzip -o "/tmp/yals_server.zip" "*/web/*" -d "/tmp/yals_extract/"
  cp -r /tmp/yals_extract/*/web/* "$WEB_DIR/"
  rm -rf "/tmp/yals_extract" "/tmp/yals_server.zip"

  # Update systemd service
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=YALS Server
After=network.target

[Service]
Type=simple
ExecStart=$SERVER_BIN -c $CONFIG_FILE -w $WEB_DIR
Restart=always
RestartSec=5s
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl restart yals.service

  echo -e "${GREEN}✅ Server updated successfully${NC}"
  exit 0
fi

# ========== Install Mode ==========
echo -e "${CYAN}========== YALS SERVER Installation ==========${NC}"
echo ""

# Interactive input for server configuration
echo -e "${CYAN}Server Configuration${NC}"
echo -e "${YELLOW}-----------------------------------${NC}"

read -p "Bind Host (default: 0.0.0.0): " SERVER_HOST
SERVER_HOST=${SERVER_HOST:-"0.0.0.0"}

read -p "Server Port (default: 8080): " SERVER_PORT
SERVER_PORT=${SERVER_PORT:-8080}

read -sp "Server Password: " SERVER_PASSWORD
echo ""
while [[ -z "$SERVER_PASSWORD" ]]; do
  echo -e "${RED}Password cannot be empty${NC}"
  read -sp "Server Password: " SERVER_PASSWORD
  echo ""
done

read -p "Enable TLS? (true/false, default: false): " SERVER_TLS
SERVER_TLS=${SERVER_TLS:-false}

TLS_CERT_FILE=""
TLS_KEY_FILE=""
if [[ "$SERVER_TLS" == "true" ]]; then
  read -p "TLS Certificate File Path: " TLS_CERT_FILE
  read -p "TLS Key File Path: " TLS_KEY_FILE
fi

read -p "Log Level (debug/info/warn/error, default: info): " LOG_LEVEL
LOG_LEVEL=${LOG_LEVEL:-"info"}

echo ""
echo -e "${YELLOW}[INFO]${NC} Creating directories..."
mkdir -p "$SERVER_DIR"
mkdir -p "$WEB_DIR"

DOWNLOAD_URL=$(get_latest_download_url)
if [[ -z "$DOWNLOAD_URL" ]]; then
  echo -e "${RED}[ERROR]${NC} Failed to get download URL from GitHub Release"
  exit 1
fi

echo -e "${YELLOW}[INFO]${NC} Downloading yals_server..."
curl -L -o "/tmp/yals_server.zip" "$DOWNLOAD_URL"

echo -e "${YELLOW}[INFO]${NC} Extracting..."
unzip -o -j "/tmp/yals_server.zip" "*/yals_server" -d "/tmp/"
chmod +x "/tmp/yals_server"
mv "/tmp/yals_server" "$SERVER_BIN"

# Extract web files
echo -e "${YELLOW}[INFO]${NC} Extracting web files..."
unzip -o "/tmp/yals_server.zip" "*/web/*" -d "/tmp/yals_extract/"
cp -r /tmp/yals_extract/*/web/* "$WEB_DIR/"
rm -rf "/tmp/yals_extract" "/tmp/yals_server.zip"

# Generate configuration
echo -e "${YELLOW}[INFO]${NC} Generating configuration..."
cat > "$CONFIG_FILE" <<EOF
server:
  host: "$SERVER_HOST"
  port: $SERVER_PORT
  password: "$SERVER_PASSWORD"
  log_level: "$LOG_LEVEL"
  tls: $SERVER_TLS
  tls_cert_file: "${TLS_CERT_FILE:-./cert.pem}"
  tls_key_file: "${TLS_KEY_FILE:-./key.pem}"

websocket:
  ping_interval: 30
  pong_wait: 60

connection:
  keepalive: 86400
EOF

# systemd
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=YALS Server
After=network.target

[Service]
Type=simple
ExecStart=$SERVER_BIN -c $CONFIG_FILE -w $WEB_DIR
Restart=always
RestartSec=5s
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable yals.service
systemctl restart yals.service

echo ""
echo -e "${GREEN}✅ YALS Server installed successfully${NC}"
echo -e "${CYAN}Configuration file: $CONFIG_FILE${NC}"
echo -e "${CYAN}Web directory: $WEB_DIR${NC}"
echo -e "${CYAN}Service status: systemctl status yals${NC}"
