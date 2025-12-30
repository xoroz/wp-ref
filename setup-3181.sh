#!/bin/bash
# Automated OpenWebUI + OpenRouter setup for Ubuntu
# Run as non-root user with sudo access

set -e

USER=$(whoami)
DIR=~/openwebui

echo "=== Installing Docker on Ubuntu ==="
sudo apt update && sudo apt upgrade -y
sudo apt install ca-certificates curl -y
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
sudo usermod -aG docker $USER
newgrp docker

sleep 2
echo "Docker installed. Testing..."
docker compose version

docker run hello-world

echo "=== Creating OpenWebUI directory ==="
mkdir -p $DIR
cd $DIR

# Generate secure keys
echo "Generate your OpenRouter API key at https://openrouter.ai/keys"
read -p "Enter OpenRouter API Key (sk-or-...): " -r API_KEY

SECRET_KEY=$(openssl rand -hex 32)

echo "=== Creating docker-compose.yml ==="
cat > docker-compose.yml << EOF
version: '3.8'
services:
  openwebui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: openwebui
    restart: unless-stopped
    ports:
      - "3000:8080"
    environment:
      - WEBUI_SECRET_KEY=$SECRET_KEY
      - OPENAI_API_BASE=https://openrouter.ai/api/v1
      - OPENAI_API_KEY=$API_KEY
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

chmod 600 docker-compose.yml

echo "=== Starting OpenWebUI ==="
docker compose up -d

# Wait and check
sleep 10
echo "=== Enabling Docker services ==="
sudo systemctl enable --now docker.socket docker.service

# Firewall
sudo ufw allow 3000 &>/dev/null || true

# Status
echo "
✅ Setup complete!"
echo "🌐 Access OpenWebUI: http://localhost:3000"
echo "📊 Status:"
docker compose ps
echo "📜 Logs: docker compose logs -f openwebui"
echo "🔄 Update: cd $DIR && docker compose pull && docker compose up -d"

# Test API
if curl -s -H "Authorization: Bearer $API_KEY" https://openrouter.ai/api/v1/models | grep -q '"id"'; then
  echo "✅ OpenRouter API verified"
else
  echo "⚠️  OpenRouter API test failed - check your API key"
fi