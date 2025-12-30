#!/bin/bash
# Complete OpenWebUI + OpenRouter.ai setup script
# Usage: curl -sSL https://raw.githubusercontent.com/xoroz/wp-ref/refs/heads/main/setup-2720.sh | bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[+] $1${NC}"; }
print_warning() { echo -e "${YELLOW}[!] $1${NC}"; }
error_exit() { echo -e "${RED}[-] $1${NC}"; exit 1; }

print_status "Starting OpenWebUI setup..."

# Check if running as root
[[ $EUID -eq 0 ]] && error_exit "Do not run as root. Use sudo user."

# Update system
print_status "Updating system..."
sudo apt update && sudo apt upgrade -y

# Install Docker dependencies
print_status "Installing Docker CE..."
sudo apt install -y ca-certificates curl
gpg_dir="/etc/apt/keyrings"
sudo install -m 0755 -d $gpg_dir
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o $gpg_dir/docker.gpg
sudo chmod a+r $gpg_dir/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=$gpg_dir/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | sudo tee /etc/apt/sources.list.d/docker.list &gt; /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker &gt;/dev/null 2&gt;&amp;1 || print_warning "Please relogin for docker group changes to take effect"

# Test Docker
print_status "Testing Docker installation..."
docker run --rm hello-world &gt;/dev/null || error_exit "Docker test failed"
print_status "Docker OK"

# Create OpenWebUI directory
mkdir -p ~/openwebui
cd ~/openwebui

# Create docker-compose.yaml from context
cat &gt; docker-compose.yaml &lt;&lt; 'EOF'
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    environment:
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - OPENAI_API_BASE_URL=https://openrouter.ai/api/v1
      - WEBUI_SECRET_KEY=12312300_0p3n-s3s4m3_k3y  # Change to secure random key
    volumes:
      - open-webui-data:/app/backend/data
    ports:
      - "127.0.0.1:8080:8080"
    restart: unless-stopped
volumes:
  open-webui-data:
EOF

# Create secure .env template
cat &gt; .env &lt;&lt; 'EOF'
# Get your API key from https://openrouter.ai
# OPENAI_API_KEY=sk-or-...
EOF
chmod 600 .env

print_status "Setup complete!"
print_status "1. Edit ~/.env with your OpenRouter.ai API key"
print_status "2. Run: cd ~/openwebui &amp;&amp; docker compose up -d"
print_status "3. Access: http://localhost:8080"
print_status "4. Create admin user on first visit"

# Show verification commands
cat &lt;&lt; 'EOF'

Verification:
$ docker ps | grep openwebui
$ docker logs openwebui

Update:
$ cd ~/openwebui &amp;&amp; docker compose down &amp;&amp; docker compose pull &amp;&amp; docker compose up -d
EOF