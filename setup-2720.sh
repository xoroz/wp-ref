#!/bin/bash
# Automated setup for OpenWebUI + OpenRouter on Ubuntu
# Run as non-root sudo user

set -e

# Colors
RED='\\e[31m'
GREEN='\\e[32m'
YELLOW='\\e[33m'
NC='\\e[0m'

echo -e "${GREEN}Starting OpenWebUI + OpenRouter setup...${NC}"

# Check Ubuntu
if ! grep -q 'Ubuntu' /etc/os-release 2>/dev/null; then
    echo -e "${RED}Ubuntu required!${NC}"
    exit 1
fi

read -p "Enter OpenRouter API key: " API_KEY
if [[ -z "$API_KEY" ]]; then
    echo -e "${RED}API key required!${NC}"
    exit 1
fi

read -p "Enter host port (default 3000): " PORT
PORT=${PORT:-3000}

# Update system
sudo apt update && sudo apt upgrade -y
sudo apt install ca-certificates curl gnupg lsb-release openssl -y

# Docker install (official method)
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

# User to docker group
sudo usermod -aG docker $USER
newgrp docker

# Enable services
sudo systemctl enable --now docker.socket docker.service

# Create OpenWebUI dir
mkdir -p ~/openwebui
cd ~/openwebui

# Generate secret key
SECRET_KEY=$(openssl rand -hex 32)

# Create docker-compose.yml
cat > docker-compose.yml << EOF
version: '3.8'
services:
  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: openwebui
    restart: unless-stopped
    ports:
      - "${PORT}:8080"
    environment:
      - WEBUI_SECRET_KEY=${SECRET_KEY}
      - OPENAI_API_BASE=https://openrouter.ai/api/v1
      - OPENAI_API_KEY=${API_KEY}
    volumes:
      - openwebui:/app/backend/data
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
volumes:
  openwebui:
EOF

# Firewall
sudo ufw allow ${PORT}/tcp &>/dev/null || true

# Start
docker compose up -d

# Wait and check
sleep 10
if docker ps | grep -q openwebui; then
    IP=$(curl -s ifconfig.me || hostname -I | awk '{print $1}')
    echo -e "${GREEN}✓ Success! Access at http://${IP}:${PORT}${NC}"
    echo -e "${YELLOW}Models auto-load in Admin > Connections > OpenAI${NC}"
    echo "Logs: docker logs openwebui"
    echo "Stop: cd ~/openwebui && docker compose down"
    echo "Update: docker compose pull && docker compose up -d"
else
    echo -e "${RED}Failed! Check: docker compose logs${NC}"
    exit 1
fi