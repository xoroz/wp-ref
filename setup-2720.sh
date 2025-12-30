#!/bin/bash
# Complete OpenWebUI + OpenRouter.ai setup script for Ubuntu
# Usage: curl -sL https://raw.githubusercontent.com/xoroz/wp-ref/refs/heads/main/setup-2720.sh | bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    error "Do not run as root. Use sudo user."
fi

log "Starting OpenWebUI + OpenRouter.ai setup..."

# 1. Update system
log "Updating system packages..."
sudo apt update
sudo apt upgrade -y
sudo apt install -y ca-certificates curl gnupg lsb-release

# 2. Install Docker CE
log "Installing Docker CE..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 3. Configure Docker user
groupadd -f docker || true
sudo usermod -aG docker $USER
log "User added to docker group. Please log out and back in, then re-run this script."

# Test Docker (user must relogin for this to work)
if ! docker --version &> /dev/null; then
    warn "Docker test failed - user needs to relogin"
    exit 0
fi

# 4. Enable Docker services
sudo systemctl enable docker.service containerd.service
sudo systemctl start docker

# 5. Create OpenWebUI project
log "Creating OpenWebUI project..."
mkdir -p ~/openwebui
cd ~/openwebui

# 6. Create .env file (user must edit)
cat > .env << 'EOF'
# EDIT THIS: Replace with your OpenRouter.ai API key
OPENAI_API_KEY=sk-or-v1-your_actual_openrouter_api_key_here

# Auto-generated secure secret key
WEBUI_SECRET_KEY=$(openssl rand -base64 32)
EOF

chmod 600 .env

# 7. Create docker-compose.yaml from context
cat > docker-compose.yaml << 'EOF'
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
volumes:
  open-webui-data:
EOF

# 8. Start OpenWebUI
log "Starting OpenWebUI..."
docker compose up -d

# 9. Verification
log "Verifying deployment..."
sleep 5
docker ps --filter name=openwebui
docker logs openwebui --tail 20

log "✅ Setup complete!"
log "🌐 Access OpenWebUI at: http://localhost:8080"
log "⚠️  IMPORTANT: Edit ~/.openwebui/.env with your OpenRouter.ai API key"
log "🔑 Generate secret key if needed: openssl rand -base64 32"
log "📁 Backup command: docker run --rm -v openwebui-data:/data -v $(pwd):/backup alpine tar czf /backup/openwebui-$(date +%Y%m%d).tar.gz -C /data ."
log "🔄 Update command: cd ~/openwebui && docker compose down && docker compose pull && docker compose up -d"

cat << 'EOF'

🚀 NEXT STEPS:
1. nano ~/.openwebui/.env  # Add your OpenRouter.ai API key
2. docker compose down && docker compose up -d  # Restart with env vars
3. Visit http://127.0.0.1:8080
4. Create admin account
5. Configure OpenAI connection in Settings

EOF