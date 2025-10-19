#!/usr/bin/env bash
set -euo pipefail

# Harden script for Ubuntu/Debian (works on Ubuntu 24+)
# - Enforces SSH key-only auth
# - Optionally creates sudo user and installs key
# - Configures UFW (rate-limit), fail2ban, unattended-upgrades
# Usage examples in header of assistant message.

NEW_USER=""
PUBKEY_CONTENT=""
PUBKEY_FILE=""
SSH_PORT="22"
DISABLE_ROOT="no"

log(){ echo -e "\033[1;32m[OK]\033[0m $*"; }
warn(){ echo -e "\033[1;33m[WARN]\033[0m $*"; }
err(){ echo -e "\033[1;31m[ERR]\033[0m $*" >&2; }

usage(){
  cat <<EOF
Usage: sudo bash $0 [--user NAME] [--pubkey "ssh-..."] [--pubkey-file /path/on/server.pub] [--ssh-port N] [--disable-root]

Notes:
 - --pubkey expects the full public key line (one line). Example: ssh-ed25519 AAAA...
 - --pubkey-file expects a path ON THE SERVER (e.g. /root/id_ed25519.pub). If the file does not exist,
   the script will fallback to using /root/.ssh/authorized_keys if present.
EOF
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) NEW_USER="${2:-}"; shift 2;;
    --pubkey) PUBKEY_CONTENT="${2:-}"; shift 2;;
    --pubkey-file) PUBKEY_FILE="${2:-}"; shift 2;;
    --ssh-port) SSH_PORT="${2:-}"; shift 2;;
    --disable-root) DISABLE_ROOT="yes"; shift 1;;
    -h|--help) usage; exit 0;;
    *) err "Unknown arg: $1"; usage; exit 1;;
  esac
done

# Must be root
if [[ "$EUID" -ne 0 ]]; then
  err "Run as root (use sudo)"; exit 1
fi

# If PUBKEY_FILE provided, try read it (server path)
if [[ -n "$PUBKEY_FILE" && -z "$PUBKEY_CONTENT" ]]; then
  if [[ -f "$PUBKEY_FILE" ]]; then
    PUBKEY_CONTENT="$(tr -d '\r' < "$PUBKEY_FILE")"
    log "Loaded public key from $PUBKEY_FILE"
  else
    warn "--pubkey-file $PUBKEY_FILE not found on server."
    if [[ -f /root/.ssh/authorized_keys ]]; then
      warn "Found /root/.ssh/authorized_keys. Will continue using existing authorized_keys as fallback."
    else
      err "No public key provided and /root/.ssh/authorized_keys not present. Either send .pub to server and use --pubkey-file, or use --pubkey with the public-key content."
      exit 1
    fi
  fi
fi

# If no pubkey content and /root/.ssh/authorized_keys exists, we'll proceed using that
if [[ -z "$PUBKEY_CONTENT" ]]; then
  if [[ -f /root/.ssh/authorized_keys ]]; then
    warn "No --pubkey provided; using existing /root/.ssh/authorized_keys as-is."
  else
    err "No public key available. Provide --pubkey or --pubkey-file (pointing to a file on the server)."
    exit 1
  fi
fi

# Install packages
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends openssh-server ufw fail2ban unattended-upgrades ca-certificates

log "Required packages installed."

# Create new user if requested
if [[ -n "$NEW_USER" ]]; then
  if id "$NEW_USER" &>/dev/null; then
    warn "User $NEW_USER already exists, skipping creation."
  else
    adduser --disabled-password --gecos "" "$NEW_USER"
    usermod -aG sudo "$NEW_USER"
    passwd -l "$NEW_USER" >/dev/null 2>&1 || true
    log "User $NEW_USER created and added to sudo group."
  fi

  # Install key for new user if provided
  if [[ -n "$PUBKEY_CONTENT" ]]; then
    install -d -m 700 "/home/$NEW_USER/.ssh"
    echo "$PUBKEY_CONTENT" > "/home/$NEW_USER/.ssh/authorized_keys"
    chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"
    chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"
    log "Installed public key for $NEW_USER."
  else
    warn "No public key content available to install for $NEW_USER."
  fi
fi

# Ensure root .ssh exists and add key as failsafe (if provided)
if [[ -n "$PUBKEY_CONTENT" ]]; then
  install -d -m 700 /root/.ssh
  touch /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
  if ! grep -qF "$PUBKEY_CONTENT" /root/.ssh/authorized_keys; then
    echo "$PUBKEY_CONTENT" >> /root/.ssh/authorized_keys
    log "Appended public key to /root/.ssh/authorized_keys (failsafe)."
  else
    log "Public key already present in /root/.ssh/authorized_keys."
  fi
fi

# Detect SSH systemd unit (prefer ssh.service on modern Ubuntu)
SSH_UNIT=""
if systemctl list-unit-files | grep -q '^ssh.service'; then
  SSH_UNIT="ssh"
elif systemctl list-unit-files | grep -q '^sshd.service'; then
  SSH_UNIT="sshd"
else
  # fallback: prefer 'ssh' (Ubuntu) because many modern images use that
  SSH_UNIT="ssh"
fi
log "Detected SSH unit: ${SSH_UNIT}.service"

# Backup sshd_config
SSHD_CFG="/etc/ssh/sshd_config"
if [[ -f "$SSHD_CFG" ]]; then
  cp -a "$SSHD_CFG" "${SSHD_CFG}.bak.$(date +%F_%T)"
  log "Backed up $SSHD_CFG"
fi

# Apply safe sshd_config changes (idempotent)
# We'll ensure required directives exist and set desired values.
set_config() {
  local key="$1" value="$2"
  if grep -qE "^\s*#?\s*${key}\b" "$SSHD_CFG" 2>/dev/null; then
    sed -i "s|^\s*#\?\s*${key}.*|${key} ${value}|" "$SSHD_CFG"
  else
    echo "${key} ${value}" >> "$SSHD_CFG"
  fi
}

set_config "PubkeyAuthentication" "yes"
set_config "PasswordAuthentication" "no"
set_config "ChallengeResponseAuthentication" "no"
set_config "UsePAM" "yes"
set_config "AuthorizedKeysFile" ".ssh/authorized_keys"
# Keep root by key allowed by default; you may set --disable-root to change.
if [[ "$DISABLE_ROOT" == "yes" ]]; then
  set_config "PermitRootLogin" "no"
else
  set_config "PermitRootLogin" "prohibit-password"
fi

# Set custom port if requested
if [[ "$SSH_PORT" != "22" ]]; then
  set_config "Port" "${SSH_PORT}"
fi

# Validate sshd config if binary exists
SSHD_BIN="$(command -v sshd || true)"
if [[ -z "$SSHD_BIN" ]]; then
  # try common paths
  for p in /usr/sbin/sshd /usr/local/sbin/sshd; do
    if [[ -x "$p" ]]; then SSHD_BIN="$p"; break; fi
  done
fi

if [[ -n "$SSHD_BIN" && -x "$SSHD_BIN" ]]; then
  if ! "$SSHD_BIN" -t; then
    err "sshd config test failed. Restoring backup and aborting."
    cp -a "${SSHD_CFG}.bak."* "$SSHD_CFG" 2>/dev/null || true
    systemctl restart "${SSH_UNIT}" 2>/dev/null || true
    exit 1
  else
    log "sshd config validated successfully."
  fi
else
  warn "sshd binary not found for config test; proceeding but be cautious."
fi

# Restart SSH unit (robust)
if ! systemctl restart "${SSH_UNIT}" 2>/dev/null; then
  warn "Restart of ${SSH_UNIT} failed; trying fallback names."
  systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || {
    err "Could not restart OpenSSH. Check service name and logs (journalctl -u ssh or -u sshd)."
    exit 1
  }
fi
log "OpenSSH restarted (unit: ${SSH_UNIT})."

# Setup UFW
ufw --force reset >/dev/null 2>&1 || true
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp" comment "ssh"
# rate limit (still allow explicit port)
ufw limit "${SSH_PORT}/tcp" >/dev/null 2>&1 || true
ufw --force enable
log "UFW enabled and SSH port ${SSH_PORT} allowed (rate-limited)."

# Configure fail2ban basic for sshd (jail name is 'sshd' even if systemd unit is 'ssh')
mkdir -p /etc/fail2ban/jail.d
cat >/etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled = true
port    = ${SSH_PORT}
filter  = sshd
logpath = %(sshd_log)s
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
EOF

systemctl enable --now fail2ban
log "fail2ban enabled and started."

# Unattended upgrades
cat >/etc/apt/apt.conf.d/20auto-upgrades <<'AUTO'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
AUTO

apt-get install -y unattended-upgrades >/dev/null 2>&1 || true
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive unattended-upgrades || true
log "Unattended-upgrades configured."

# Final message
echo
log "HARDENING FINISHED"
echo " - SSH only by key (PasswordAuthentication=no)."
if [[ "$DISABLE_ROOT" == "yes" ]]; then
  echo " - Root login via SSH: DISABLED"
else
  echo " - Root login via SSH: allowed by key (PermitRootLogin=prohibit-password)"
fi
echo " - SSH port: ${SSH_PORT}"
[[ -n "$NEW_USER" ]] && echo " - Created sudo user: ${NEW_USER}"
echo " - UFW active; fail2ban active; unattended-upgrades enabled."
echo
echo "IMPORTANT: Before closing this session, test a NEW SSH connection in another terminal:"
if [[ "$SSH_PORT" == "22" ]]; then
  echo "  ssh -i ~/.ssh/id_ed25519 ${NEW_USER:-root}@<YOUR_IP>"
else
  echo "  ssh -p ${SSH_PORT} -i ~/.ssh/id_ed25519 ${NEW_USER:-root}@<YOUR_IP>"
fi
echo
log "Done."

