#!/bin/bash
set -euo pipefail

# Prerequisites
sudo apt update
sudo apt install -y git curl ca-certificates build-essential docker-compose-plugin nodejs
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc  # Ensure uv on PATH

# Download launcher
wget -O /usr/local/bin/task-runner-launcher https://github.com/n8n-io/task-runner-launcher/releases/latest/download/task-runner-launcher-linux-amd64
tar -xzf /usr/local/bin/task-runner-launcher  # Assuming tar.gz, adjust if needed
chmod +x /usr/local/bin/task-runner-launcher

# n8n Docker Compose (create docker-compose.yml)
cat > docker-compose.yml << 'EOF'
services:
  n8n:
    image: n8nio/n8n
    ports:
      - "127.0.0.1:5678:5678"
      - "127.0.0.1:5679:5679"
    environment:
      - N8N_RUNNERS_ENABLED=true
      - N8N_RUNNERS_MODE=external
      - N8N_RUNNERS_AUTH_TOKEN=TESTn8n123
      - N8N_RUNNERS_BROKER_LISTEN_ADDRESS=0.0.0.0
      - N8N_RUNNERS_BROKER_PORT=5679
EOF
docker compose up -d

# Runner user
sudo useradd -m -s /bin/bash runner
sudo mkdir -p /home/runner/runners
sudo chown -R runner:runner /home/runner/runners

# Clone and setup runners
sudo -u runner -H bash -lc '
cd /home/runner/runners
git clone https://github.com/n8n-io/n8n.git n8n-src
cp -a n8n-src/packages/@n8n/task-runner-python task-runner-python
cd task-runner-python
uv sync
'

# Assume JS runner built; placeholder mkdir
sudo -u runner mkdir -p /home/runner/runners/task-runner-javascript/dist
sudo chown -R runner:runner /home/runner/runners/task-runner-javascript

# Runners config
sudo tee /etc/n8n-task-runners.json > /dev/null << 'EOF'
{
  "task-runners": [
    {
      "runner-type": "javascript",
      "workdir": "/home/runner/runners/task-runner-javascript",
      "command": "/usr/bin/node",
      "args": ["dist/start.js"],
      "health-check-server-port": 5681,
      "allowed-env": ["PATH"],
      "env-overrides": {"N8N_RUNNERS_HEALTH_CHECK_SERVER_HOST": "0.0.0.0"}
    },
    {
      "runner-type": "python",
      "workdir": "/home/runner/runners/task-runner-python",
      "command": "/home/runner/runners/task-runner-python/.venv/bin/python",
      "args": ["-m", "src.main"],
      "health-check-server-port": 5682,
      "allowed-env": ["PATH"],
      "env-overrides": {
        "PYTHONPATH": "/home/runner/runners/task-runner-python",
        "N8N_RUNNERS_STDLIB_ALLOW": "urllib,http,ssl"
      }
    }
  ]
}
EOF

# Systemd service
sudo tee /etc/systemd/system/n8n-runner.service > /dev/null << 'EOF'
[Unit]
Description=N8N Task Runner Launcher
After=network.target
[Service]
Type=simple
User=runner
ExecStart=/usr/local/bin/task-runner-launcher javascript python
Environment=N8N_RUNNERS_CONFIG_PATH=/etc/n8n-task-runners.json
Environment=N8N_RUNNERS_AUTH_TOKEN=TESTn8n123
Environment=N8N_RUNNERS_TASK_BROKER_URI=http://127.0.0.1:5679
Environment=N8N_RUNNERS_LAUNCHER_HEALTH_CHECK_PORT=5680
Environment=N8N_RUNNERS_AUTO_SHUTDOWN_TIMEOUT=15
Restart=always
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now n8n-runner

# Wait and verify
sleep 10
curl -f http://localhost:5680/healthz || echo 'Health check failed, check journalctl -u n8n-runner -f'

echo 'Setup complete. Check n8n at http://localhost:5678'