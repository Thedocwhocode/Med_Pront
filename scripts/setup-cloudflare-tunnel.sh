#!/usr/bin/env bash
# T011 — Cloudflare Tunnel setup: install cloudflared, authenticate, configure tunnel
set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash $0" >&2
  exit 1
fi

TUNNEL_NAME="${CF_TUNNEL_NAME:-med-pront}"
DOMAIN="${TRAEFIK_DOMAIN:-yourdomain.com}"
CLOUDFLARED_CONFIG_DIR=/etc/cloudflared

log "=== Step 1: Install cloudflared ==="
if command -v cloudflared &>/dev/null; then
  log "cloudflared already installed: $(cloudflared --version)"
else
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
    | gpg --dearmor -o /usr/share/keyrings/cloudflare-main.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/cloudflared.list
  apt-get update -qq
  apt-get install -y cloudflared
  log "cloudflared installed: $(cloudflared --version)"
fi

log "=== Step 2: Create tunnel ==="
# If TUNNEL_TOKEN is set in env, use it directly (preferred for Docker)
if [[ -n "${CF_TUNNEL_TOKEN:-}" ]]; then
  log "CF_TUNNEL_TOKEN found — tunnel will authenticate via token."
  log "Ensure docker/.env contains CF_TUNNEL_TOKEN and redeploy with: docker compose up -d cloudflare-tunnel"
  exit 0
fi

# Interactive: authenticate and create tunnel manually
log "No CF_TUNNEL_TOKEN set. Starting interactive authentication..."
log "A browser window will open. Log in to your Cloudflare account."
cloudflared tunnel login

log "Creating tunnel: $TUNNEL_NAME"
cloudflared tunnel create "$TUNNEL_NAME"

TUNNEL_ID=$(cloudflared tunnel list --output json | python3 -c \
  "import sys, json; tunnels=json.load(sys.stdin); \
   t=[x for x in tunnels if x['name']=='$TUNNEL_NAME']; \
   print(t[0]['id'] if t else '')")

if [[ -z "$TUNNEL_ID" ]]; then
  log "ERROR: Could not find tunnel ID for '$TUNNEL_NAME'"
  exit 1
fi
log "Tunnel ID: $TUNNEL_ID"

log "=== Step 3: Configure tunnel routing ==="
mkdir -p "$CLOUDFLARED_CONFIG_DIR"
cat > "$CLOUDFLARED_CONFIG_DIR/config.yml" << EOF
tunnel: $TUNNEL_ID
credentials-file: /root/.cloudflared/$TUNNEL_ID.json

ingress:
  - hostname: $DOMAIN
    service: http://traefik:80
  - service: http_status:404
EOF

log "=== Step 4: Route DNS ==="
cloudflared tunnel route dns "$TUNNEL_NAME" "$DOMAIN"
log "DNS route created: $DOMAIN -> $TUNNEL_NAME"

log "=== Step 5: Install as system service ==="
cloudflared service install
systemctl enable cloudflared
systemctl start cloudflared
log "cloudflared service started."

log ""
log "=== Tunnel setup complete ==="
log "Add CF_TUNNEL_TOKEN to docker/.env for container-based tunnel."
cloudflared tunnel info "$TUNNEL_NAME" || true
