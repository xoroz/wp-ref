docker-compose.yml 
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
      #- N8N_HOST=${N8N_HOST:-n8n.texgo.it}
      #- N8N_PORT=${N8N_PORT:-443}
      #- N8N_PROTOCOL=${N8N_PROTOCOL:-https}
      - WEBHOOK_URL=https://n8n.texgo.it/
      - N8N_PROXY_HOPS=1
      - NODE_ENV=production
      - OPENROUTER_API_KEY=${OPEN_API_KEY}
      - OPENROUTER_BASE_URL=https://openrouter.ai/api/v1
      - OPENROUTER_MODEL=x-ai/grok-code-fast-1 # Default model
    extra_hosts:
      - "felipeferreira.net:51.178.46.243"      
volumes:
  n8n_data:
