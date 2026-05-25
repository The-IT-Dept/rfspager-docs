#!/bin/bash
set -e

# RFSPager.app Installer
# https://github.com/the-it-dept/rfspager-docs

INSTALL_DIR="/opt/rfspager"
IMAGE="ghcr.io/the-it-dept/rfspager-client:sha-cd86e5d"

# Frequencies
RFS_FREQ="148.5875M"
FRNSW_FREQ="148.9625M"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Check for root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This installer must be run as root${NC}"
    echo "Please run: curl -fsSL https://raw.githubusercontent.com/the-it-dept/rfspager-docs/main/agent.sh | sudo bash"
    exit 1
fi

# When invoked via `curl ... | sudo bash`, fd 0 is the pipe carrying the script
# itself — bash reads it incrementally. We must NOT replace fd 0 with /dev/tty
# (that would make bash try to read further script lines from the terminal and
# hang). Instead, open /dev/tty on fd 3 and have each `read` use it explicitly.
if [ -t 0 ]; then
    exec 3<&0
elif [ -r /dev/tty ]; then
    exec 3</dev/tty
else
    echo -e "${RED}Error: No terminal available for interactive prompts.${NC}"
    echo "Run the installer directly instead of piping it, e.g.:"
    echo "  curl -fsSL https://raw.githubusercontent.com/the-it-dept/rfspager-docs/main/agent.sh -o agent.sh"
    echo "  sudo bash agent.sh"
    exit 1
fi

echo -e "${CYAN}"
echo "  ____  _____ ____  ____                           "
echo " |  _ \|  ___/ ___||  _ \ __ _  __ _  ___ _ __     "
echo " | |_) | |_  \___ \| |_) / _\` |/ _\` |/ _ \ '__|  "
echo " |  _ <|  _|  ___) |  __/ (_| | (_| |  __/ |       "
echo " |_| \_\_|   |____/|_|   \__,_|\__, |\___|_|       "
echo "                               |___/               "
echo -e "${NC}"
echo -e "${BOLD}RFSPager.app Agent Installer${NC}"
echo -e "For NSW Rural Fire Service & Fire and Rescue NSW"
echo "=================================================="
echo

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect RTL-SDR devices
detect_rtl_devices() {
    echo -e "${YELLOW}Detecting RTL-SDR devices...${NC}" >&2

    # Run rtl_test briefly to count devices
    RTL_OUTPUT=$(timeout 2 rtl_test 2>&1 || true)

    if echo "$RTL_OUTPUT" | grep -q "No supported devices found"; then
        RTL_COUNT=0
    else
        # Extract the number from "Found X device(s):"
        RTL_COUNT=$(echo "$RTL_OUTPUT" | sed -n 's/Found \([0-9]*\) device.*/\1/p' | head -1)
    fi

    # Fallback: check lsusb for RTL devices if rtl_test didn't work
    if [ -z "$RTL_COUNT" ] || [ "$RTL_COUNT" -eq 0 ]; then
        RTL_COUNT=$(lsusb | grep -ciE "(RTL|0bda:2838|0bda:2832)" || echo "0")
    fi

    echo "$RTL_COUNT"
}

# ============================================
# STEP 1: Install Dependencies
# ============================================
echo -e "${BOLD}Step 1: Installing Dependencies${NC}"
echo "--------------------------------"

# Update package list
echo "Updating package list..."
apt-get update -qq

# Install RTL-SDR packages
echo "Installing RTL-SDR packages..."
apt-get install -y -qq rtl-sdr librtlsdr-dev libusb-1.0-0-dev curl > /dev/null

# Blacklist DVB drivers (required for RTL-SDR)
if [ ! -f /etc/modprobe.d/blacklist-rtlsdr.conf ]; then
    echo "Blacklisting DVB kernel modules..."
    echo -e "blacklist dvb_usb_rtl28xxu\nblacklist rtl2832\nblacklist rtl2830" | tee /etc/modprobe.d/blacklist-rtlsdr.conf > /dev/null
    echo -e "${YELLOW}Note: You may need to reboot for RTL-SDR to work properly.${NC}"
fi

# Add udev rules for RTL-SDR
if [ ! -f /etc/udev/rules.d/rtl-sdr.rules ]; then
    echo "Adding udev rules for RTL-SDR..."
    echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2838", GROUP="plugdev", MODE="0666"' | tee /etc/udev/rules.d/rtl-sdr.rules > /dev/null
    udevadm control --reload-rules
    udevadm trigger
fi

echo -e "${GREEN}✓ RTL-SDR packages installed${NC}"

# ============================================
# STEP 2: Install Docker
# ============================================
echo
echo -e "${BOLD}Step 2: Checking Docker${NC}"
echo "-----------------------"

if command_exists docker; then
    echo -e "${GREEN}✓ Docker is already installed${NC}"
else
    echo -e "${YELLOW}Installing Docker...${NC}"
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    echo -e "${GREEN}✓ Docker installed${NC}"
fi

# Ensure docker is running
if ! docker info >/dev/null 2>&1; then
    systemctl start docker
    sleep 2
fi

# Check for Docker Compose
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command_exists docker-compose; then
    COMPOSE_CMD="docker-compose"
else
    echo "Installing Docker Compose plugin..."
    apt-get install -y -qq docker-compose-plugin > /dev/null
    COMPOSE_CMD="docker compose"
fi
echo -e "${GREEN}✓ Docker Compose available${NC}"

# ============================================
# STEP 3: Detect RTL-SDR Hardware
# ============================================
echo
echo -e "${BOLD}Step 3: Detecting RTL-SDR Hardware${NC}"
echo "-----------------------------------"

RTL_COUNT=$(detect_rtl_devices)

if [ "$RTL_COUNT" -eq 0 ]; then
    echo -e "${RED}⚠ No RTL-SDR devices detected!${NC}"
    echo
    echo "Please ensure your RTL-SDR dongle(s) are plugged in."
    echo "If you just plugged them in, you may need to reboot first."
    echo
    read -u 3 -p "Continue anyway? (y/N): " CONTINUE_ANYWAY
    if [[ ! "$CONTINUE_ANYWAY" =~ ^[Yy]$ ]]; then
        echo "Installation cancelled. Please connect your RTL-SDR device(s) and try again."
        exit 1
    fi
    RTL_COUNT=1
    echo -e "${YELLOW}Proceeding with assumed 1 device...${NC}"
elif [ "$RTL_COUNT" -eq 1 ]; then
    echo -e "${GREEN}✓ Found 1 RTL-SDR device${NC}"
else
    echo -e "${GREEN}✓ Found $RTL_COUNT RTL-SDR devices${NC}"
fi

# ============================================
# STEP 4: User Configuration
# ============================================
echo
echo -e "${BOLD}Step 4: Configuration${NC}"
echo "---------------------"
echo

# Get API Key
while true; do
    if ! read -u 3 -p "Enter your RFSPager API Key: " API_KEY; then
        echo -e "${RED}Error: stdin closed before API key was entered.${NC}" >&2
        exit 1
    fi
    if [ -z "$API_KEY" ]; then
        echo -e "${RED}API Key cannot be empty. Please try again.${NC}"
    else
        break
    fi
done

# Get Site Name
echo
echo "Enter a site name for this agent (e.g., 'hornsby', 'central-coast')"
echo "This will be used to identify your agent in the system."
while true; do
    if ! read -u 3 -p "Site Name: " SITE_NAME; then
        echo -e "${RED}Error: stdin closed before site name was entered.${NC}" >&2
        exit 1
    fi
    if [ -z "$SITE_NAME" ]; then
        echo -e "${RED}Site name cannot be empty. Please try again.${NC}"
    else
        # Sanitize site name (lowercase, replace spaces with dashes)
        SITE_NAME=$(echo "$SITE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
        break
    fi
done

# Service Selection
echo
echo -e "${BOLD}Select which services to monitor:${NC}"
echo

if [ "$RTL_COUNT" -ge 2 ]; then
    echo "You have $RTL_COUNT RTL-SDR devices. You can monitor both services!"
    echo
    echo "  1) RFS only       (NSW Rural Fire Service - 148.5875 MHz)"
    echo "  2) FRNSW only     (Fire and Rescue NSW - 148.9625 MHz)"
    echo "  3) Both RFS and FRNSW (requires 2 RTL-SDR devices)"
    echo
    while true; do
        if ! read -u 3 -p "Select option [1-3]: " SERVICE_CHOICE; then
            echo -e "${RED}Error: stdin closed before a service was selected.${NC}" >&2
            exit 1
        fi
        case $SERVICE_CHOICE in
            1) SERVICES="rfs"; break;;
            2) SERVICES="frnsw"; break;;
            3) SERVICES="both"; break;;
            *) echo -e "${RED}Please enter 1, 2, or 3${NC}";;
        esac
    done
else
    echo "You have 1 RTL-SDR device. Select one service to monitor:"
    echo
    echo "  1) RFS    (NSW Rural Fire Service - 148.5875 MHz)"
    echo "  2) FRNSW  (Fire and Rescue NSW - 148.9625 MHz)"
    echo
    while true; do
        if ! read -u 3 -p "Select option [1-2]: " SERVICE_CHOICE; then
            echo -e "${RED}Error: stdin closed before a service was selected.${NC}" >&2
            exit 1
        fi
        case $SERVICE_CHOICE in
            1) SERVICES="rfs"; break;;
            2) SERVICES="frnsw"; break;;
            *) echo -e "${RED}Please enter 1 or 2${NC}";;
        esac
    done
fi

# ============================================
# STEP 5: Generate docker-compose.yml
# ============================================
echo
echo -e "${BOLD}Step 5: Generating Configuration${NC}"
echo "---------------------------------"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Start compose file
cat > docker-compose.yml << EOF
version: '3.9'

services:
EOF

DEVICE_INDEX=0

# Add FRNSW service if selected
if [ "$SERVICES" = "frnsw" ] || [ "$SERVICES" = "both" ]; then
    cat >> docker-compose.yml << EOF
  frnsw:
    image: ${IMAGE}
    container_name: rfspager-frnsw
    restart: unless-stopped
    environment:
      PAGERMON_APIKEY: ${API_KEY}
      PAGERMON_IDENTIFIER: rfspager-${SITE_NAME} (FRNSW)
      PAGER_DEVICE: "${DEVICE_INDEX}"
      PAGER_FREQUENCY: ${FRNSW_FREQ}
      TZ: Australia/Sydney
    devices:
      - /dev/bus/usb
    volumes:
      - /etc/localtime:/etc/localtime:ro
EOF
    DEVICE_INDEX=$((DEVICE_INDEX + 1))
    echo -e "${GREEN}✓ FRNSW service configured (Device $((DEVICE_INDEX - 1)), ${FRNSW_FREQ})${NC}"
fi

# Add RFS service if selected
if [ "$SERVICES" = "rfs" ] || [ "$SERVICES" = "both" ]; then
    cat >> docker-compose.yml << EOF
  rfs:
    image: ${IMAGE}
    container_name: rfspager-rfs
    restart: unless-stopped
    environment:
      PAGERMON_APIKEY: ${API_KEY}
      PAGERMON_IDENTIFIER: rfspager-${SITE_NAME} (RFS)
      PAGER_DEVICE: "${DEVICE_INDEX}"
      PAGER_FREQUENCY: ${RFS_FREQ}
      TZ: Australia/Sydney
    devices:
      - /dev/bus/usb
    volumes:
      - /etc/localtime:/etc/localtime:ro
EOF
    echo -e "${GREEN}✓ RFS service configured (Device ${DEVICE_INDEX}, ${RFS_FREQ})${NC}"
fi

echo -e "${GREEN}✓ docker-compose.yml created at ${INSTALL_DIR}/docker-compose.yml${NC}"

# ============================================
# STEP 6: Start Services
# ============================================
echo
echo -e "${BOLD}Step 6: Starting RFSPager Agent${NC}"
echo "--------------------------------"

echo "Pulling Docker image..."
$COMPOSE_CMD pull

echo "Starting containers..."
$COMPOSE_CMD up -d

# ============================================
# Complete!
# ============================================
echo
echo -e "${GREEN}=================================================${NC}"
echo -e "${GREEN}   ✓ RFSPager.app Installation Complete!${NC}"
echo -e "${GREEN}=================================================${NC}"
echo
echo -e "${BOLD}Configuration Summary:${NC}"
echo "  Site Name:    ${SITE_NAME}"
echo "  Services:     ${SERVICES^^}"
echo "  Install Dir:  ${INSTALL_DIR}"
echo "  Image:        ${IMAGE}"
echo
echo -e "${BOLD}Useful Commands:${NC}"
echo "  cd ${INSTALL_DIR}"
echo "  ${COMPOSE_CMD} logs -f        # View live logs"
echo "  ${COMPOSE_CMD} ps             # Check status"
echo "  ${COMPOSE_CMD} restart        # Restart services"
echo "  ${COMPOSE_CMD} down           # Stop services"
echo "  ${COMPOSE_CMD} pull && ${COMPOSE_CMD} up -d  # Update"
echo
echo -e "${BOLD}View your agent at:${NC} https://rfspager.app"
echo
echo -e "${CYAN}Thank you for contributing to RFSPager.app!${NC}"
