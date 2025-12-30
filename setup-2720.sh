#!/bin/bash
# Complete OpenWebUI + OpenRouter.ai setup script for Ubuntu
# Usage: OPENAI_API_KEY=your_key ./setup.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if OPENAI_API_KEY is set
if [ -z "$OPENAI_API_KEY" ]; then
    echo -e "${RED}ERROR: Set OPENAI_API_KEY environment variable${NC}"
    echo "Example: OPENAI_API_KEY=sk-... ./setup.sh"
    exit 1
fi

echo -e "${GREEN}Starting OpenWebUI + OpenRouter.ai installation...${NC}"

# Update system
sudo apt update
sudo apt upgrade -y
sudo apt install -y ca-certificates curl gnupg lsb-release

# Install Docker
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Enable Docker services
sudo systemctl enable docker.service containerd.service
sudo systemctl start docker.service

# Create project directory
mkdir -p ~/openwebui
cd ~/openwebui

# Create custom network and volume
docker network create openwebui-net 2>/dev/null || true
docker volume create open-webui-data 2>/dev/null || true

# Generate secure secret key
WEBUI_SECRET_KEY=$(openssl rand -hex 32)

# Create docker-compose.yaml
cat > docker-compose.yaml << EOF
services:
  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    environment:
      - OPENAI_API_KEY=${OPENAI_API_KEY}
      - OPENAI_API_BASE_URL=https://openrouter.ai/api/v1
      - WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}
    volumes:
      - open-webui-data:/app/backend/data
    ports:
      - "127.0.0.1:8080:8080"
    restart: unless-stopped
    networks:
      - openwebui-net

volumes:
  open-webui-data:

networks:
  openwebui-net:
    external: true
EOF

# Start OpenWebUI
docker compose up -d

# Wait for startup
sleep 10

# Show status
echo -e "\n${GREEN}✓ Installation complete!${NC}"
echo -e "${GREEN}✓ Access OpenWebUI at: http://localhost:8080${NC}"
echo -e "${GREEN}✓ Generated WEBUI_SECRET_KEY: ${WEBUI_SECRET_KEY}${NC}"
echo

docker ps --filter name=open-webui
docker logs open-webui --tail 10

echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Open http://localhost:8080"
echo "2. Create admin user"
echo "3. OpenRouter.ai models auto-configured"

echo -e "\n${GREEN}Success! OpenWebUI ready with OpenRouter.ai integration.${NC}"