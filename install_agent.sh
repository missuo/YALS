#!/bin/bash
# install_agent.sh - YALS Agent Installer / Updater (GitHub Release Version)

set -e

REPO="missuo/YALS"

AGENT_DIR="/etc/yals"
AGENT_BIN="/usr/bin/yals_agent"
CONFIG_FILE="$AGENT_DIR/agent.yaml"
SERVICE_FILE="/etc/systemd/system/yals_agent.service"

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

# ========= Update Mode ==========
if [[ "$1" == "update" ]]; then
  echo -e "${CYAN}========== YALS AGENT Update Mode ==========${NC}"

  DOWNLOAD_URL=$(get_latest_download_url)
  if [[ -z "$DOWNLOAD_URL" ]]; then
    echo -e "${RED}[ERROR]${NC} Failed to get download URL from GitHub Release"
    exit 1
  fi

  echo -e "${YELLOW}[INFO]${NC} Downloading latest agent: $DOWNLOAD_URL"
  curl -L -o "/tmp/yals_agent.zip" "$DOWNLOAD_URL"
  
  echo -e "${YELLOW}[INFO]${NC} Extracting..."
  unzip -o -j "/tmp/yals_agent.zip" "*/yals_agent" -d "/tmp/"
  chmod +x "/tmp/yals_agent"
  mv "/tmp/yals_agent" "$AGENT_BIN"
  rm -f "/tmp/yals_agent.zip"

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=YALS Agent
After=network.target

[Service]
Type=simple
ExecStart=$AGENT_BIN -c $CONFIG_FILE
Restart=always
RestartSec=5s
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl restart yals_agent.service

  echo -e "${GREEN}✅ Agent updated successfully${NC}"
  exit 0
fi

# ========= Install Mode ==========
echo -e "${CYAN}========== YALS AGENT Installation ==========${NC}"
echo ""

# Interactive input for server configuration
echo -e "${CYAN}Server Configuration${NC}"
echo -e "${YELLOW}-----------------------------------${NC}"

read -p "Server Host (e.g., lg.example.com): " SERVER_HOST
while [[ -z "$SERVER_HOST" ]]; do
  echo -e "${RED}Server host cannot be empty${NC}"
  read -p "Server Host: " SERVER_HOST
done

read -p "Server Port (default: 443): " SERVER_PORT
SERVER_PORT=${SERVER_PORT:-443}

read -sp "Server Password: " SERVER_PASSWORD
echo ""
while [[ -z "$SERVER_PASSWORD" ]]; do
  echo -e "${RED}Password cannot be empty${NC}"
  read -sp "Server Password: " SERVER_PASSWORD
  echo ""
done

read -p "Use TLS? (true/false, default: true): " SERVER_TLS
SERVER_TLS=${SERVER_TLS:-true}

echo ""
echo -e "${CYAN}Agent Configuration${NC}"
echo -e "${YELLOW}-----------------------------------${NC}"

read -p "Agent Name (e.g., Node 1): " AGENT_NAME
AGENT_NAME=${AGENT_NAME:-"Agent"}

read -p "Agent Group (e.g., Location A): " AGENT_GROUP
AGENT_GROUP=${AGENT_GROUP:-"Default"}

read -p "Location (e.g., Tokyo, Japan): " DETAIL_LOCATION
DETAIL_LOCATION=${DETAIL_LOCATION:-"Unknown"}

read -p "Datacenter (e.g., AWS Tokyo): " DETAIL_DATACENTER
DETAIL_DATACENTER=${DETAIL_DATACENTER:-"Unknown"}

read -p "Test IP (optional): " DETAIL_TEST_IP
DETAIL_TEST_IP=${DETAIL_TEST_IP:-""}

read -p "Description (optional): " DETAIL_DESC
DETAIL_DESC=${DETAIL_DESC:-""}

echo ""
echo -e "${YELLOW}[INFO]${NC} Creating directories..."
mkdir -p "$AGENT_DIR"

DOWNLOAD_URL=$(get_latest_download_url)
if [[ -z "$DOWNLOAD_URL" ]]; then
  echo -e "${RED}[ERROR]${NC} Failed to get download URL from GitHub Release"
  exit 1
fi

echo -e "${YELLOW}[INFO]${NC} Downloading yals_agent..."
curl -L -o "/tmp/yals_agent.zip" "$DOWNLOAD_URL"

echo -e "${YELLOW}[INFO]${NC} Extracting..."
unzip -o -j "/tmp/yals_agent.zip" "*/yals_agent" -d "/tmp/"
chmod +x "/tmp/yals_agent"
mv "/tmp/yals_agent" "$AGENT_BIN"
rm -f "/tmp/yals_agent.zip"

# Install tcping
install_tcping() {
  echo -e "${YELLOW}[INFO]${NC} Installing tcping..."
  local arch=$(detect_arch)
  local tcping_url=""
  
  if [[ "$arch" == "amd64" ]]; then
    tcping_url="https://github.com/pouriyajamshidi/tcping/releases/download/v2.7.1/tcping-linux-amd64-dynamic.tar.gz"
  elif [[ "$arch" == "arm64" ]]; then
    tcping_url="https://github.com/pouriyajamshidi/tcping/releases/download/v2.7.1/tcping-linux-arm64-dynamic.tar.gz"
  else
    echo -e "${RED}[WARN]${NC} Unsupported architecture for tcping: $arch, skipping..."
    return
  fi
  
  curl -L -o "/tmp/tcping.tar.gz" "$tcping_url"
  tar -xzf "/tmp/tcping.tar.gz" -C "/tmp/"
  mv "/tmp/tcping" "/usr/local/bin/tcping"
  chmod +x "/usr/local/bin/tcping"
  rm -f "/tmp/tcping.tar.gz"
  echo -e "${GREEN}[OK]${NC} tcping installed successfully"
}

# Install nexttrace
install_nexttrace() {
  echo -e "${YELLOW}[INFO]${NC} Installing nexttrace..."
  curl -sL nxtrace.org/nt | bash
  echo -e "${GREEN}[OK]${NC} nexttrace installed successfully"
}

# Install additional tools
echo ""
echo -e "${CYAN}Installing Additional Tools${NC}"
echo -e "${YELLOW}-----------------------------------${NC}"

install_tcping || echo -e "${RED}[WARN]${NC} Failed to install tcping, skipping..."
install_nexttrace || echo -e "${RED}[WARN]${NC} Failed to install nexttrace, skipping..."

# Generate configuration
echo -e "${YELLOW}[INFO]${NC} Generating configuration..."
cat > "$CONFIG_FILE" <<EOF
server:
  host: "$SERVER_HOST"
  port: $SERVER_PORT
  password: "$SERVER_PASSWORD"
  tls: $SERVER_TLS

agent:
  name: "$AGENT_NAME"
  group: "$AGENT_GROUP"
  details:
    location: "$DETAIL_LOCATION"
    datacenter: "$DETAIL_DATACENTER"
    test_ip: "$DETAIL_TEST_IP"
    description: "$DETAIL_DESC"

commands:
  ping:
    template: "ping -c 4"
    description: "Network connectivity test"

  tcping:
    template: "tcping -c 4 {host} {port}"
    description: "TCP connectivity test"
    default_port: "80"

  mtr:
    template: "mtr -rw -c 4"
    description: "Network route and packet loss analysis"

  nexttrace:
    template: "nexttrace --no-color"
    description: "Advanced network route tracing"
EOF

# systemd
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=YALS Agent
After=network.target

[Service]
Type=simple
ExecStart=$AGENT_BIN -c $CONFIG_FILE
Restart=always
RestartSec=5s
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable yals_agent.service
systemctl restart yals_agent.service

echo ""
echo -e "${GREEN}✅ YALS Agent installed successfully${NC}"
echo -e "${CYAN}Configuration file: $CONFIG_FILE${NC}"
echo -e "${CYAN}Service status: systemctl status yals_agent${NC}"
