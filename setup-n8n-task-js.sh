#!/usr/bin/env bash
# setup-task-js.sh
#
# Builds and installs the n8n JavaScript task runner (@n8n/task-runner) on the host
# in a minimal “deployed” folder, then (optionally) updates /etc/n8n-task-runners.json
# and restarts the n8n-runner systemd service.
#
# Goal: avoid keeping a full 2–3GB n8n monorepo checkout on disk.
#
# Usage:
#   sudo ./setup-task-js.sh
#   sudo N8N_TAG="n8n@2.2.0" ./setup-task-js.sh      # recommended: match your n8n container version/tag
#
set -euo pipefail

### Configurable bits
RUNNER_USER="${RUNNER_USER:-runner}"
RUNNER_HOME="$(getent passwd "$RUNNER_USER" | cut -d: -f6 2>/dev/null || true)"
RUNNERS_BASE="${RUNNERS_BASE:-/home/${RUNNER_USER}/runners}"
TARGET_DIR="${TARGET_DIR:-${RUNNERS_BASE}/task-runner-javascript}"
CONFIG_JSON="${CONFIG_JSON:-/etc/n8n-task-runners.json}"
N8N_TAG="${N8N_TAG:-}"   # e.g. "n8n@2.2.0" (best to match your n8n docker image)

# If you want the script to rewrite the JS runner block in CONFIG_JSON:
UPDATE_CONFIG="${UPDATE_CONFIG:-1}"  # 1=yes, 0=no

### Helpers
log() { printf '\n[%s] %s\n' "$(date +'%F %T')" "$*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Run as root (use sudo)."
}

ensure_user() {
  if ! id "$RUNNER_USER" >/dev/null 2>&1; then
    log "Creating user: $RUNNER_USER"
    useradd -m -s /bin/bash "$RUNNER_USER"
  fi

  RUNNER_HOME="$(getent passwd "$RUNNER_USER" | cut -d: -f6)"
  [[ -n "$RUNNER_HOME" ]] || die "Could not determine home for user $RUNNER_USER"
  mkdir -p "$RUNNERS_BASE"
  chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_HOME" "$RUNNERS_BASE"
}

ver_ge() { # ver_ge 22.16.0 22.21.0  => true
  # crude semver compare using sort -V
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" == "$1" ]]
}

ensure_node22() {
  if command -v node >/dev/null 2>&1; then
    local v
    v="$(node -p "process.versions.node" 2>/dev/null || true)"
    if [[ -n "$v" ]] && ver_ge "22.16.0" "$v"; then
      log "Node is installed (v$v)"
      return 0
    fi
    log "Node exists but is too old (v${v:-unknown}). Need >= 22.16.0"
  else
    log "Node is not installed. Need >= 22.16.0"
  fi

  log "Installing Node.js 22.x (NodeSource)"
  apt-get update -y
  apt-get install -y curl ca-certificates gnupg
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
  apt-get install -y nodejs

  local nv
  nv="$(node -p "process.versions.node")"
  ver_ge "22.16.0" "$nv" || die "Node install did not meet requirement (got v$nv)"
  log "Node installed: v$nv at $(command -v node)"
}

ensure_tools() {
  log "Installing build tools (git, jq, etc.)"
  apt-get update -y
  apt-get install -y git jq ca-certificates curl build-essential
}

build_and_deploy() {
  local tmp_root repo_dir store_dir node_bin
  node_bin="$(command -v node)"
  [[ -x "$node_bin" ]] || die "node not executable"

  tmp_root="$(mktemp -d -t n8n-task-runner-js-XXXXXX)"
  repo_dir="${tmp_root}/n8n-src"
  store_dir="${tmp_root}/pnpm-store"

  log "Working in temp dir: $tmp_root"
  log "Cloning n8n repo (shallow)${N8N_TAG:+ at tag $N8N_TAG}"
  if [[ -n "$N8N_TAG" ]]; then
    sudo -u "$RUNNER_USER" -H bash -lc "git clone --depth 1 --branch '$N8N_TAG' https://github.com/n8n-io/n8n.git '$repo_dir'"
  else
    sudo -u "$RUNNER_USER" -H bash -lc "git clone --depth 1 https://github.com/n8n-io/n8n.git '$repo_dir'"
  fi

  log "Installing deps ONLY for @n8n/task-runner and its dependency chain (keeps install smaller)"
  # Use an isolated pnpm store inside the temp dir so we don't leave a huge global cache behind.
  sudo -u "$RUNNER_USER" -H bash -lc "
    set -e
    cd '$repo_dir'
    corepack enable
    pnpm config set store-dir '$store_dir'
    pnpm config set fund false
    pnpm config set audit false

    # Install only what's needed for @n8n/task-runner + deps
    pnpm install --filter '@n8n/task-runner...' --prefer-frozen-lockfile
  "

  log "Building @n8n/task-runner (and required workspace deps)"
  sudo -u "$RUNNER_USER" -H bash -lc "
    set -e
    cd '$repo_dir'
    pnpm --filter '@n8n/task-runner...' run build
    test -f 'packages/@n8n/task-runner/dist/start.js'
  "

  log "Deploying a minimal runtime folder to: $TARGET_DIR"
  rm -rf "$TARGET_DIR"
  mkdir -p "$TARGET_DIR"
  chown -R "$RUNNER_USER:$RUNNER_USER" "$TARGET_DIR"

  # Key: inject workspace packages so deploy contains @n8n/* workspace deps.
  sudo -u "$RUNNER_USER" -H bash -lc "
    set -e
    cd '$repo_dir'
    pnpm config set inject-workspace-packages true
    pnpm --filter '@n8n/task-runner' deploy --prod '$TARGET_DIR'
  "

  log "Removing non-runtime sources from deploy folder (extra size savings)"
  # Keep dist/, package.json, node_modules/. Remove src/tests/docs/maps where safe.
  rm -rf "${TARGET_DIR}/src" "${TARGET_DIR}/test" "${TARGET_DIR}/tests" "${TARGET_DIR}/__tests__" 2>/dev/null || true
  find "$TARGET_DIR" -type f -name "*.map" -delete 2>/dev/null || true
  find "$TARGET_DIR" -type f -name "*.ts" -delete 2>/dev/null || true
  find "$TARGET_DIR" -maxdepth 2 -type f -name "tsconfig*.json" -delete 2>/dev/null || true
  chown -R "$RUNNER_USER:$RUNNER_USER" "$TARGET_DIR"

  log "Verifying deployed JS runner can resolve workspace deps (e.g. @n8n/di) and start file exists"
  test -f "${TARGET_DIR}/dist/start.js" || die "Missing ${TARGET_DIR}/dist/start.js"
  test -f "${TARGET_DIR}/node_modules/@n8n/di/package.json" || die "Deploy missing @n8n/di (inject-workspace-packages likely not applied)"

  log "Temporary build directory cleanup"
  rm -rf "$tmp_root"

  log "Deployed folder size:"
  du -sh "$TARGET_DIR" || true
}

update_runner_config() {
  [[ "$UPDATE_CONFIG" == "1" ]] || { log "Skipping config update (UPDATE_CONFIG=0)"; return 0; }

  [[ -f "$CONFIG_JSON" ]] || die "Config not found: $CONFIG_JSON"
  local node_bin
  node_bin="$(command -v node)"

  log "Updating JS runner block in $CONFIG_JSON (using jq)"
  # Replace the entry where runner-type == "javascript"
  # Sets: workdir, command, args to the deployed folder.
  tmp="$(mktemp)"
  jq --arg workdir "$TARGET_DIR" \
     --arg node "$node_bin" \
     --arg start "${TARGET_DIR}/dist/start.js" \
     '
     ."task-runners" |= (map(
       if ."runner-type" == "javascript" then
         .workdir = $workdir
         | .command = $node
         | .args = ["--disallow-code-generation-from-strings","--disable-proto=delete",$start]
       else .
       end
     ))
     ' "$CONFIG_JSON" > "$tmp"

  install -m 0644 "$tmp" "$CONFIG_JSON"
  rm -f "$tmp"
  log "Config updated."
}

restart_service() {
  if systemctl list-unit-files | grep -q '^n8n-runner\.service'; then
    log "Restarting n8n-runner.service"
    systemctl daemon-reload
    systemctl restart n8n-runner
    log "Recent logs:"
    journalctl -u n8n-runner -n 60 --no-pager || true
  else
    log "n8n-runner.service not found; not restarting anything."
  fi
}

main() {
  require_root
  ensure_tools
  ensure_node22
  ensure_user
  build_and_deploy
  update_runner_config
  restart_service

  cat <<EOF

Done.

JS runner folder:
  $TARGET_DIR
Entry file:
  $TARGET_DIR/dist/start.js

If n8n-runner is running, you can now test in n8n with a Code node (JavaScript):

  return [{ json: { ok: true, msg: "JS runner works", ts: new Date().toISOString() } }];

EOF
}

main "$@"
