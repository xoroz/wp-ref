#!/bin/bash
# Automated n8n setup script for Ubuntu
# Co-authored by AI

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" &amp;&amp; exit 1; }

# Check root
[[ $EUID -ne 0 ]] &amp;&amp; error "Run as root (sudo)"

log "Updating system..."
apt update &amp;&amp; apt install -y docker.io docker-compose-plugin haproxy certbot

log "Creating n8n directory..."
mkdir -p /opt/n8n-setup &amp;&amp; cd /opt/n8n-setup

log "Creating docker-compose.yml..."
cat &gt; docker-compose.yml &lt;&lt; 'EOF'
services:
  n8n:
    image: n8nio/n8n
    ports:
      - "127.0.0.1:5678:5678"
    volumes:
      - n8n_data:/home/node/.n8n
    restart: unless-stopped
    environment:
      - N8N_BLOCK_ENV_ACCESS_IN_NODE=false
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=false
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASSWORD}
      - WEBHOOK_URL=https://n8n.texgo.it/
      - N8N_PROXY_HOPS=1
      - NODE_ENV=production
      - OPENROUTER_API_KEY=${OPEN_API_KEY}
      - OPENROUTER_BASE_URL=https://openrouter.ai/api/v1
      - OPENROUTER_MODEL=x-ai/grok-code-fast-1
    extra_hosts:
      - "felipeferreira.net:51.178.46.243"      
volumes:
  n8n_data:
EOF

log "Creating .env template (EDIT BEFORE USE!)"
cat &gt; .env &lt;&lt; 'EOF'
N8N_PASSWORD=change_me_immediately
OPEN_API_KEY=your_openrouter_api_key_here
EOF
log "⚠️  Edit .env: nano .env (set strong N8N_PASSWORD &amp; OPEN_API_KEY)"

log "Starting n8n..."
docker compose up -d

log "n8n running on localhost:5678 (admin/CHANGE_ME)"
log "Verifying..."
sleep 5
if docker ps | grep n8n; then
  log "✅ n8n is running!"
else
  error "n8n failed to start. Check: docker compose logs"
fi

log "HAProxy setup (replace DOMAIN in next steps)"
read -p "Enter your domain (e.g., n8n.example.com): " DOMAIN

log "Getting SSL cert..."
certbot certonly --standalone -d $DOMAIN
cat /etc/letsencrypt/live/$DOMAIN/fullchain.pem /etc/letsencrypt/live/$DOMAIN/privkey.pem &gt; /etc/haproxy/n8n.pem
chown haproxy:haproxy /etc/haproxy/n8n.pem
chmod 600 /etc/haproxy/n8n.pem

log "Configuring HAProxy..."
cat &gt;&gt; /etc/haproxy/haproxy.cfg &lt;&lt; EOF
listen n8n-https
    bind *:443 ssl crt /etc/haproxy/n8n.pem
    mode http
    server n8n_app 127.0.0.1:5678 check
EOF

systemctl restart haproxy
log "✅ Complete! Access https://$DOMAIN"
log "Next: Edit /opt/n8n-setup/.env, docker compose down &amp;&amp; up -d"
log "HAProxy logs: journalctl -u haproxy -f"
