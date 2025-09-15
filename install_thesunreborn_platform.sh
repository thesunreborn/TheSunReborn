#!/bin/bash
set -euo pipefail

#=============================================================================
# TheSunReborn Healing Platform - Auto Installer
# Supports: Ubuntu, Debian, CentOS, RHEL, Fedora, Arch, openSUSE
#=============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PLATFORM_DIR="$HOME/healing-platform"
SERVICES_DIR="$PLATFORM_DIR/services"
COMPOSE_FILE="$PLATFORM_DIR/docker-compose.yml"
LOG_FILE="$PLATFORM_DIR/install.log"

# Package manager detection based on multiple sources [web:211][web:215]
detect_package_manager() {
    echo -e "${BLUE}Detecting package manager...${NC}"
    
    # Declare associative array for distribution detection [web:217]
    declare -A osInfo
    osInfo[/etc/debian_version]="apt"
    osInfo[/etc/alpine-release]="apk"
    osInfo[/etc/centos-release]="yum"
    osInfo[/etc/fedora-release]="dnf"
    osInfo[/etc/arch-release]="pacman"
    osInfo[/etc/SuSE-release]="zypper"
    
    # Check for package managers using command detection [web:211]
    if command -v apt > /dev/null 2>&1; then
        PKG_MANAGER="apt"
        PKG_INSTALL="apt install -y"
        PKG_UPDATE="apt update"
    elif command -v dnf > /dev/null 2>&1; then
        PKG_MANAGER="dnf"
        PKG_INSTALL="dnf install -y"
        PKG_UPDATE="dnf check-update"
    elif command -v yum > /dev/null 2>&1; then
        PKG_MANAGER="yum"
        PKG_INSTALL="yum install -y"
        PKG_UPDATE="yum check-update"
    elif command -v pacman > /dev/null 2>&1; then
        PKG_MANAGER="pacman"
        PKG_INSTALL="pacman -S --noconfirm"
        PKG_UPDATE="pacman -Sy"
    elif command -v zypper > /dev/null 2>&1; then
        PKG_MANAGER="zypper"
        PKG_INSTALL="zypper install -y"
        PKG_UPDATE="zypper refresh"
    elif command -v apk > /dev/null 2>&1; then
        PKG_MANAGER="apk"
        PKG_INSTALL="apk add"
        PKG_UPDATE="apk update"
    else
        # Fallback to file-based detection [web:217]
        for f in "${!osInfo[@]}"; do
            if [[ -f $f ]]; then
                PKG_MANAGER=${osInfo[$f]}
                break
            fi
        done
    fi
    
    # Detect distribution using os-release [web:215][web:224]
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO="$ID"
        VERSION="$VERSION_ID"
    elif [[ -f /usr/lib/os-release ]]; then
        . /usr/lib/os-release
        DISTRO="$ID"
        VERSION="$VERSION_ID"
    else
        DISTRO="unknown"
        VERSION="unknown"
    fi
    
    echo -e "${GREEN}Detected: ${DISTRO} ${VERSION} with ${PKG_MANAGER}${NC}"
}

# Install core dependencies based on package manager [web:211]
install_core_dependencies() {
    echo -e "${BLUE}Installing core dependencies...${NC}"
    
    # Update package lists
    sudo $PKG_UPDATE || true
    
    # Common packages across all distributions
    case "$PKG_MANAGER" in
        "apt")
            sudo $PKG_INSTALL curl wget git build-essential software-properties-common \
                apt-transport-https ca-certificates gnupg lsb-release
            ;;
        "yum"|"dnf")
            sudo $PKG_INSTALL curl wget git gcc gcc-c++ make dnf-plugins-core
            ;;
        "pacman")
            sudo $PKG_INSTALL curl wget git base-devel
            ;;
        "zypper")
            sudo $PKG_INSTALL curl wget git gcc gcc-c++ make
            ;;
        "apk")
            sudo $PKG_INSTALL curl wget git build-base
            ;;
        *)
            echo -e "${RED}Unsupported package manager: $PKG_MANAGER${NC}"
            exit 1
            ;;
    esac
}

# Install Node.js LTS
install_nodejs() {
    echo -e "${BLUE}Installing Node.js LTS...${NC}"
    
    if command -v node > /dev/null 2>&1; then
        echo -e "${GREEN}Node.js already installed: $(node --version)${NC}"
        return
    fi
    
    case "$PKG_MANAGER" in
        "apt")
            curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
            sudo $PKG_INSTALL nodejs
            ;;
        "yum"|"dnf")
            curl -fsSL https://rpm.nodesource.com/setup_lts.x | sudo bash -
            sudo $PKG_INSTALL nodejs npm
            ;;
        "pacman")
            sudo $PKG_INSTALL nodejs npm
            ;;
        "zypper")
            sudo zypper ar https://rpm.nodesource.com/pub_lts.x/el/7/x86_64 nodesource
            sudo zypper refresh
            sudo $PKG_INSTALL nodejs npm
            ;;
    esac
}

# Install Docker and Docker Compose v2 [web:191][web:203]
install_docker() {
    echo -e "${BLUE}Installing Docker and Docker Compose...${NC}"
    
    if command -v docker > /dev/null 2>&1; then
        echo -e "${GREEN}Docker already installed: $(docker --version)${NC}"
    else
        case "$PKG_MANAGER" in
            "apt")
                # Official Docker installation for Ubuntu/Debian [web:203]
                curl -fsSL https://download.docker.com/linux/$DISTRO/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$DISTRO $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
                sudo apt update
                sudo $PKG_INSTALL docker-ce docker-ce-cli containerd.io docker-compose-plugin
                ;;
            "yum"|"dnf")
                sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                sudo $PKG_INSTALL docker-ce docker-ce-cli containerd.io docker-compose-plugin
                ;;
            *)
                # Fallback to distribution packages
                sudo $PKG_INSTALL docker docker-compose
                ;;
        esac
        
        # Start and enable Docker service [web:198][web:202]
        sudo systemctl enable --now docker
        sudo usermod -aG docker "$USER"
        echo -e "${YELLOW}Please log out and log back in for Docker group changes to take effect${NC}"
    fi
    
    # Verify Docker Compose v2 [web:191][web:196]
    if docker compose version &>/dev/null; then
        echo -e "${GREEN}Docker Compose v2 installed: $(docker compose version)${NC}"
    else
        echo -e "${RED}Docker Compose v2 not available, installing standalone...${NC}"
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    fi
}

# Install Visual Studio Code
install_vscode() {
    echo -e "${BLUE}Installing Visual Studio Code...${NC}"
    
    if command -v code > /dev/null 2>&1; then
        echo -e "${GREEN}VS Code already installed${NC}"
        return
    fi
    
    case "$PKG_MANAGER" in
        "apt")
            wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
            sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
            sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/trusted.gpg.d/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
            sudo apt update
            sudo $PKG_INSTALL code
            rm packages.microsoft.gpg
            ;;
        "yum"|"dnf")
            sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
            sudo sh -c 'echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/vscode.repo'
            sudo $PKG_INSTALL code
            ;;
        *)
            echo -e "${YELLOW}Please install VS Code manually for your distribution${NC}"
            ;;
    esac
}

# Create project structure
create_project_structure() {
    echo -e "${BLUE}Creating project structure...${NC}"
    
    mkdir -p "$PLATFORM_DIR"
    mkdir -p "$SERVICES_DIR"
    mkdir -p "$PLATFORM_DIR/frontend"
    mkdir -p "$PLATFORM_DIR/mobile"
    mkdir -p "$PLATFORM_DIR/hardware"
    mkdir -p "$PLATFORM_DIR/ml"
    mkdir -p "$PLATFORM_DIR/k8s"
    mkdir -p "$PLATFORM_DIR/scripts"
    
    echo -e "${GREEN}Project directories created in $PLATFORM_DIR${NC}"
}

# Create Docker Compose file for databases
create_docker_compose() {
    echo -e "${BLUE}Creating Docker Compose configuration...${NC}"
    
    cat <<'YAML' > "$COMPOSE_FILE"
version: '3.8'
services:
  mongodb:
    image: mongo:7.0
    container_name: healing-mongodb
    restart: unless-stopped
    ports:
      - "27017:27017"
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: healing2025
    volumes:
      - mongodb_data:/data/db
    networks:
      - healing-network

  postgres:
    image: timescale/timescaledb:2.11.0-pg15
    container_name: healing-postgres
    restart: unless-stopped
    ports:
      - "5432:5432"
    environment:
      POSTGRES_DB: healing_platform
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: healing2025
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - healing-network

  redis:
    image: redis:7.2-alpine
    container_name: healing-redis
    restart: unless-stopped
    ports:
      - "6379:6379"
    command: redis-server --appendonly yes --requirepass healing2025
    volumes:
      - redis_data:/data
    networks:
      - healing-network

  # Optional: MongoDB Express for database management
  mongo-express:
    image: mongo-express:latest
    container_name: healing-mongo-express
    restart: unless-stopped
    ports:
      - "8081:8081"
    environment:
      ME_CONFIG_MONGODB_ADMINUSERNAME: admin
      ME_CONFIG_MONGODB_ADMINPASSWORD: healing2025
      ME_CONFIG_MONGODB_URL: mongodb://admin:healing2025@mongodb:27017/
    depends_on:
      - mongodb
    networks:
      - healing-network

volumes:
  mongodb_data:
  postgres_data:
  redis_data:

networks:
  healing-network:
    driver: bridge
YAML
    
    echo -e "${GREEN}Docker Compose file created at $COMPOSE_FILE${NC}"
}

# Create systemd service for auto-starting databases [web:213][web:225]
create_systemd_service() {
    echo -e "${BLUE}Creating systemd service for auto-startup...${NC}"
    
    # Create systemd service file [web:219][web:225]
    cat <<EOF | sudo tee /etc/systemd/system/thesunreborn-platform.service > /dev/null
[Unit]
Description=TheSunReborn Healing Platform Services
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$PLATFORM_DIR
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable service [web:219][web:225]
    sudo systemctl daemon-reload
    sudo systemctl enable thesunreborn-platform.service
    
    echo -e "${GREEN}Systemd service created and enabled${NC}"
}

# Create development launcher script
create_launcher_script() {
    echo -e "${BLUE}Creating development launcher script...${NC}"
    
    cat <<'SCRIPT' > "$PLATFORM_DIR/scripts/launch_dev_env.sh"
#!/bin/bash
# TheSunReborn Development Environment Launcher

PLATFORM_DIR="$HOME/healing-platform"

# Function to check if service is running
check_service() {
    if docker compose -f "$PLATFORM_DIR/docker-compose.yml" ps | grep -q "$1.*Up"; then
        echo -e "\033[0;32m✓ $1 is running\033[0m"
    else
        echo -e "\033[0;31m✗ $1 is not running\033[0m"
    fi
}

# Start databases if not running
echo "Starting TheSunReborn Platform databases..."
cd "$PLATFORM_DIR"
docker compose up -d

echo
echo "Service Status:"
check_service "mongodb"
check_service "postgres"
check_service "redis"

echo
echo "Access URLs:"
echo "- MongoDB: mongodb://admin:healing2025@localhost:27017"
echo "- PostgreSQL: postgresql://postgres:healing2025@localhost:5432/healing_platform"
echo "- Redis: redis://:healing2025@localhost:6379"
echo "- Mongo Express: http://localhost:8081"

echo
echo "Development environment ready!"
echo "Run 'docker compose logs -f' to view logs"
echo "Run 'docker compose down' to stop services"
SCRIPT
    
    chmod +x "$PLATFORM_DIR/scripts/launch_dev_env.sh"
    
    # Create desktop shortcut if desktop environment detected
    if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
        cat <<EOF > "$HOME/Desktop/TheSunReborn-Platform.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=TheSunReborn Platform
Comment=Launch TheSunReborn Healing Platform Development Environment
Exec=gnome-terminal -- bash -c "$PLATFORM_DIR/scripts/launch_dev_env.sh; read"
Icon=applications-development
Terminal=false
Categories=Development;
EOF
        chmod +x "$HOME/Desktop/TheSunReborn-Platform.desktop"
        echo -e "${GREEN}Desktop shortcut created${NC}"
    fi
}

# Generate SSH key for GitHub access
setup_git_ssh() {
    echo -e "${BLUE}Setting up Git SSH access...${NC}"
    
    SSH_KEY="$HOME/.ssh/id_ed25519"
    if [[ ! -f "$SSH_KEY" ]]; then
        echo "Generating SSH key for GitHub..."
        ssh-keygen -t ed25519 -C "thesunreborn@healingplatform.local" -f "$SSH_KEY" -N ""
        
        echo -e "${YELLOW}Add this SSH public key to your GitHub account:${NC}"
        echo -e "${GREEN}$(cat "${SSH_KEY}.pub")${NC}"
        echo
        echo "Go to: https://github.com/settings/ssh/new"
        read -p "Press Enter after adding the key to GitHub..."
    else
        echo -e "${GREEN}SSH key already exists${NC}"
    fi
}

# Create README and documentation
create_documentation() {
    echo -e "${BLUE}Creating documentation...${NC}"
    
    cat <<'README' > "$PLATFORM_DIR/README.md"
# TheSunReborn Healing Platform

## Quick Start

1. **Launch Development Environment**:

