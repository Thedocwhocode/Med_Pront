#!/usr/bin/env bash
# T008 — VPS hardening: SSH key-only, fail2ban, UFW (Cloudflare IPs only), unattended-upgrades
set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Cloudflare IPv4 ranges (2024-stable list)
CF_IPS_V4=(
  173.245.48.0/20
  103.21.244.0/22
  103.22.200.0/22
  103.31.4.0/22
  141.101.64.0/18
  108.162.192.0/18
  190.93.240.0/20
  188.114.96.0/20
  197.234.240.0/22
  198.41.128.0/17
  162.158.0.0/15
  104.16.0.0/13
  104.24.0.0/14
  172.64.0.0/13
  131.0.72.0/22
)

CF_IPS_V6=(
  2400:cb00::/32
  2606:4700::/32
  2803:f800::/32
  2405:b500::/32
  2405:8100::/32
  2a06:98c0::/29
  2c0f:f248::/32
)

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo bash $0" >&2
  exit 1
fi

log "=== Step 1: System update ==="
apt-get update -qq
apt-get upgrade -y -qq

log "=== Step 2: Install required packages ==="
apt-get install -y -qq ufw fail2ban unattended-upgrades apt-listchanges curl

log "=== Step 3: SSH hardening (key-only) ==="
SSHD_CONF=/etc/ssh/sshd_config
cp "$SSHD_CONF" "${SSHD_CONF}.bak.$(date +%s)"
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONF"
sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$SSHD_CONF"
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin without-password/' "$SSHD_CONF"
sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONF"
grep -q "^MaxAuthTries" "$SSHD_CONF" || echo "MaxAuthTries 3" >> "$SSHD_CONF"
grep -q "^LoginGraceTime" "$SSHD_CONF" || echo "LoginGraceTime 30" >> "$SSHD_CONF"
systemctl reload sshd
log "SSH: password auth disabled, key-only enabled."

log "=== Step 4: fail2ban ==="
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd

[sshd]
enabled = true
port    = ssh
EOF
systemctl enable fail2ban
systemctl restart fail2ban
log "fail2ban: configured (SSH, 3600s ban, 5 retries)."

log "=== Step 5: UFW — allow Cloudflare IPs only ==="
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh comment 'SSH (key-only)'

for ip in "${CF_IPS_V4[@]}"; do
  ufw allow from "$ip" to any port 80,443 proto tcp comment "Cloudflare IPv4"
done
for ip in "${CF_IPS_V6[@]}"; do
  ufw allow from "$ip" to any port 80,443 proto tcp comment "Cloudflare IPv6"
done

ufw --force enable
log "UFW: enabled, inbound 80/443 restricted to Cloudflare IPs."

log "=== Step 6: Unattended upgrades ==="
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
  "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Mail "root";
EOF
systemctl enable unattended-upgrades
log "Unattended upgrades: enabled (security only, no auto-reboot)."

log "=== VPS hardening complete ==="
ufw status verbose
fail2ban-client status sshd || true
