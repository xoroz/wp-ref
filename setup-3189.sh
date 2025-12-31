#!/bin/bash
# n8n Task Runner Launcher Complete Setup Script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
auth_token="${N8N_RUNNERS_AUTH_TOKEN:-change-me-secure-token}"
config_path="/etc/n8n-task-runners.json"
broker_uri="${N8N_RUNNERS_TASK_BROKER_URI:-http://127.0.0.1:5679}"

check_prereqs() {
    echo -e "${GREEN}Checking prerequisites...${NC}"
    command -v wget >/dev/null 2>&1 || { echo -e "${RED}wget required${NC}"; exit 1; }
    command -v tar >/dev/null 2>&1 || { echo -e "${RED}tar required${NC}"; exit 1; }
    command -v curl >/dev/null 2>&1 || { echo -e "${RED}curl required${NC}"; exit 1; }
}

download_launcher() {
    echo -e "${GREEN}Downloading latest task-runner-launcher...${NC}"
    arch=$(uname -m)
    case $arch in
        x86_64) suffix="linux-amd64" ;;
        aarch64|arm64) suffix="linux-arm64" ;;
        *) echo -e "${RED}Unsupported architecture: $arch${NC}"; exit 1 ;;
    esac
#https://github.com/n8n-io/task-runner-launcher/releases/download/1.4.2/task-runner-launcher-1.4.2-linux-amd64.tar.gz

    wget -O task-runner-launcher-${suffix}.tar.gz https://github.com/n8n-io/task-runner-launcher/releases/download/1.4.2/task-runner-launcher-1.4.2-$suffix.tar.gz

    tar -xzf task-runner-launcher-${suffix}.tar.gz
    chmod +x task-runner-launcher
    rm task-runner-launcher-${suffix}.tar.gz
    echo -e "${GREEN}Launcher downloaded: $(pwd)/task-runner-launcher${NC}"
}

create_config() {
    echo -e "${GREEN}Creating config file...${NC}"
    mkdir -p /etc
    cat > $config_path << 'EOF'
{
  "task-runners": [
    {
      "runner-type": "javascript",
      "workdir": "/opt/n8n/scripts",
      "command": "node",
      "args": [],
      "health-check-server-port": "5681",
      "allowed-env": ["PATH", "NODE_PATH"],
      "env-overrides": {"LOG_LEVEL": "info"}
    },
    {
      "runner-type": "python",
      "workdir": "/opt/n8n/scripts",
      "command": "python3",
      "args": ["-u"],
      "health-check-server-port": "5682",
      "allowed-env": ["PATH", "PYTHONPATH"],
      "env-overrides": {"LOG_LEVEL": "info"}
    }
  ]
}
EOF
    echo -e "${GREEN}Config created: $config_path${NC}"
    mkdir -p /opt/n8n/scripts
    echo -e "${GREEN}Created workdir: /opt/n8n/scripts${NC}"
}

setup_environment() {
    echo -e "${GREEN}Setting environment variables...${NC}"
    export N8N_RUNNERS_CONFIG_PATH=$config_path
    export N8N_RUNNERS_AUTH_TOKEN=$auth_token
    export N8N_RUNNERS_TASK_BROKER_URI=$broker_uri
    export N8N_RUNNERS_LAUNCHER_HEALTH_CHECK_PORT=5680
}

start_launcher() {
    echo -e "${GREEN}Starting launcher (javascript + python)...${NC}"
    ./task-runner-launcher javascript python
}

verify_health() {
    echo -e "${GREEN}Verifying health checks...${NC}"
    sleep 3
    curl -f http://localhost:5680/healthz || { echo -e "${RED}Launcher health check failed${NC}"; exit 1; }
    curl -f http://localhost:5679/healthz || echo -e "${YELLOW}Broker health check (n8n side)${NC}"
    echo -e "${GREEN}Health checks passed!${NC}"
}

show_status() {
    echo -e "\n${GREEN}=== SETUP COMPLETE ===${NC}"
    echo "Launcher: http://localhost:5680/healthz"
    echo "Config: $config_path"
    echo "To stop: Ctrl+C"
    echo "Set N8N_RUNNERS_AUTH_TOKEN in your n8n instance too!"
}

# Main execution
check_prereqs
download_launcher
create_config
setup_environment
start_launcher &
verify_health
show_status
wait
