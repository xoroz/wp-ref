
# Running n8n “external” Task Runners (JavaScript + Python) on Ubuntu (self-hosted runner, n8n in Docker)

This guide shows how to run **n8n task runners on the host (systemd)** while keeping **n8n itself in Docker Compose**, so you can execute **Python in the Code node** (and keep JavaScript runner external too).

It’s based on a working setup using:

- n8n container exposing the **Task Broker** on `127.0.0.1:5679`
- a host service running: `task-runner-launcher javascript python`
- runner configs in `/etc/n8n-task-runners.json`
- Python runner from `n8n` repo: `packages/@n8n/task-runner-python` (managed with `uv`)

---

## Architecture (what talks to what)

- **n8n (Docker)** runs the **Task Broker** on port `5679`
- **task-runner-launcher (host)** connects to `http://127.0.0.1:5679`, offers runners, and spawns processes
- **python runner process (host)** starts, registers with broker, executes tasks from the Code node
- **import allowlists** control what Python can import (security)

Ports used in this guide:
- `5678`: n8n UI/API
- `5679`: task broker (must be reachable by the host launcher)
- `5680`: launcher health check
- `5681`: JS runner health check
- `5682`: Python runner health check

---

## Prerequisites on Ubuntu host

Install basics:

```bash
sudo apt update
sudo apt install -y git curl ca-certificates build-essential
```

You also need on the host:
- Docker + docker-compose plugin (already assumed working)
- Node.js (for the JS runner) and `node` at the path you configure (example: `/usr/local/bin/node`)
- Python + `uv` (Python runner uses `uv` per upstream README)

Install `uv` (host):

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
# ensure uv is on PATH for the runner user too (often ends up in ~/.local/bin)
```

---

## 1) n8n Docker Compose: enable external runners + broker port

Your `docker-compose.yml` (as you already have) must expose the broker port to localhost:

```yaml
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
```

Bring up n8n:

```bash
docker compose up -d
```

---

## 2) Create a dedicated host user for runners

```bash
sudo useradd -m -s /bin/bash runner
sudo mkdir -p /home/runner/runners
sudo chown -R runner:runner /home/runner/runners
```

---

## 3) Get the runner source code (from the n8n repo)

Clone the n8n repo as the `runner` user (ideally checkout a tag matching your n8n version):

```bash
sudo -u runner -H bash -lc '
cd /home/runner/runners
git clone https://github.com/n8n-io/n8n.git n8n-src
'
```

### Python runner: copy the package to your runner directory

```bash
sudo -u runner -H bash -lc '
rm -rf /home/runner/runners/task-runner-python
cp -a /home/runner/runners/n8n-src/packages/@n8n/task-runner-python /home/runner/runners/task-runner-python
'
```

Install deps using `uv`:

```bash
sudo -u runner -H bash -lc '
cd /home/runner/runners/task-runner-python
uv sync
'
```

> Note: Running the python runner manually (`python -m src.main`) will complain about `N8N_RUNNERS_GRANT_TOKEN`. That’s normal: the **launcher** injects that token when it spawns the runner.

### JavaScript runner
You already have your JS runner running from:

`/home/runner/runners/task-runner-javascript/dist/start.js`

How you build that `dist/` depends on the repo tooling/version. The important part for this guide is: the file exists and is executable by user `runner`, and Node is installed.

---

## 4) Create the runners config: `/etc/n8n-task-runners.json`

Create:

```bash
sudo tee /etc/n8n-task-runners.json >/dev/null <<'JSON'
{
  "task-runners": [
    {
      "runner-type": "javascript",
      "workdir": "/home/runner/runners/task-runner-javascript",
      "command": "/usr/local/bin/node",
      "args": [
        "--disallow-code-generation-from-strings",
        "--disable-proto=delete",
        "/home/runner/runners/task-runner-javascript/dist/start.js"
      ],
      "health-check-server-port": "5681",
      "allowed-env": [
        "PATH",
        "GENERIC_TIMEZONE",
        "NODE_OPTIONS",
        "N8N_RUNNERS_AUTO_SHUTDOWN_TIMEOUT",
        "N8N_RUNNERS_TASK_TIMEOUT",
        "N8N_RUNNERS_MAX_CONCURRENCY",
        "N8N_SENTRY_DSN",
        "N8N_VERSION",
        "ENVIRONMENT",
        "DEPLOYMENT_NAME",
        "HOME"
      ],
      "env-overrides": {
        "NODE_FUNCTION_ALLOW_BUILTIN": "crypto",
        "NODE_FUNCTION_ALLOW_EXTERNAL": "moment",
        "N8N_RUNNERS_HEALTH_CHECK_SERVER_HOST": "0.0.0.0"
      }
    },
    {
      "runner-type": "python",
      "workdir": "/home/runner/runners/task-runner-python",
      "command": "/home/runner/runners/task-runner-python/.venv/bin/python",
      "args": ["-m", "src.main"],
      "health-check-server-port": "5682",
      "allowed-env": [
        "PATH",
        "N8N_RUNNERS_LAUNCHER_LOG_LEVEL",
        "N8N_RUNNERS_AUTO_SHUTDOWN_TIMEOUT",
        "N8N_RUNNERS_TASK_TIMEOUT",
        "N8N_RUNNERS_MAX_CONCURRENCY",
        "N8N_SENTRY_DSN",
        "N8N_VERSION",
        "ENVIRONMENT",
        "DEPLOYMENT_NAME"
      ],
      "env-overrides": {
        "PYTHONPATH": "/home/runner/runners/task-runner-python",
        "N8N_RUNNERS_STDLIB_ALLOW": "urllib,http,ssl",
        "N8N_RUNNERS_EXTERNAL_ALLOW": ""
      }
    }
  ]
}
JSON
```

### Important: Python import security allowlists
- `N8N_RUNNERS_STDLIB_ALLOW` is for **standard library** modules (example: `urllib`, `ssl`, `json`, etc.)
- `N8N_RUNNERS_EXTERNAL_ALLOW` is for **pip/uv installed** modules (example: `requests`)

If you want `requests`, do:

- install it:
  ```bash
  sudo -u runner -H bash -lc '
  cd /home/runner/runners/task-runner-python
  uv add requests
  uv sync
  '
  ```
- allow it:
  ```json
  "N8N_RUNNERS_EXTERNAL_ALLOW": "requests,urllib3,certifi,idna,charset_normalizer"
  ```

(Those extra names are common transitive dependencies; add what the error message asks for.)

---

## 5) Create the systemd unit for the launcher

Create `/etc/systemd/system/n8n-runner.service`:

```ini
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
Environment=N8N_RUNNERS_LAUNCHER_LOG_LEVEL=debug
Restart=always

[Install]
WantedBy=multi-user.target
```

Enable + start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now n8n-runner
```

Watch logs:

```bash
journalctl -u n8n-runner -f
```

When it’s healthy, you’ll see the runner connect and accept tasks (similar to what you posted: “Connected to broker”, “Accepted task”, “Completed task …”).

---

## 6) Test Python in n8n (Code node)

In the n8n UI:
1. Create workflow → add **Code** node
2. Set **Language: Python**
3. Use a minimal test:

```python
return [{"json": {"ok": True, "msg": "python runner works"}}]
```

Execute node.

### Test: “curl -I” (HEAD) using stdlib
After allowing `urllib,http,ssl` in `N8N_RUNNERS_STDLIB_ALLOW`:

```python
import urllib.request

url = "https://google.com"
req = urllib.request.Request(url, method="HEAD")

with urllib.request.urlopen(req, timeout=15) as resp:
    status = resp.status
    headers = dict(resp.headers)

return [{
    "json": {
        "url": url,
        "status": status,
        "ok": status == 200,
        "location": headers.get("Location"),
        "content_type": headers.get("Content-Type")
    }
}]
```

---

## Troubleshooting quick hits (the ones we hit)

- **`No module named 'src'`**: your `workdir`/`PYTHONPATH` were pointing at a folder that didn’t contain the runner source. Fix by copying the actual package containing `src/main.py`.
- **`No module named 'websockets'`**: you were running Python from the wrong environment (old venv). Use the `.venv` created by `uv sync`, or run via `uv run`.
- **`N8N_RUNNERS_GRANT_TOKEN is required`** when running manually: expected. Only the launcher injects it.
- **“Security violations… stdlib module disallowed”**: add the module(s) to `N8N_RUNNERS_STDLIB_ALLOW` and restart `n8n-runner`.

---

## “How can you fully use Python now?”
Practically:
- You can write Python in the Code node, return items (`return [{"json": ...}]`)
- You can use stdlib modules you explicitly allow
- You can use third-party modules by:
  1) installing them into `/home/runner/runners/task-runner-python` via `uv add ...`
  2) allowlisting them in `N8N_RUNNERS_EXTERNAL_ALLOW`
  3) restarting `n8n-runner`

If you share your n8n version/tag and how you built `task-runner-launcher` + the JS runner `dist`, I can add a “pin versions + build from source” section so a new host setup is fully
reproducible end-to-end.


ref
https://docs.n8n.io/hosting/configuration/task-runners/#configuring-n8n-container-in-external-mode
https://docs.n8n.io/hosting/configuration/task-runners/#2-build-your-custom-image
