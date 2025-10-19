#!/usr/bin/env bash
set -euo pipefail

# Harden Ubuntu/Debian for SSH key-only auth + UFW + Fail2ban + Unattended upgrades
# Works on Ubuntu (systemd unit: ssh) and Debian (unit: sshd) — auto-detects.

NEW_USER=""
PUBKEY_CONTENT=""
PUBKEY_FILE=""
SSH_PORT="22"
DISABLE_ROOT="no"

log()  { echo -e "\033[1;32m[OK]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err()  { echo -e "\033[1;31m[ERR]\033[0m  $*" >&2; }

usage() {
  cat <<EOF
Usage: sudo bash $0 [--user NAME] [--pubkey "ssh-..."] [--pubkey-file PATH] [--ssh-port N] [--disable-root]

Options:
  --user NAME         Cria usuário sudo NAME e instala a chave nele.
  --pubkey "ssh-..."  Conteúdo da chave pública (uma linha).
  --pubkey-file PATH  Caminho para arquivo .pub (ex: ~/.ssh/id_ed25519.pub).
  --ssh-port N        Troca porta do SSH (padrão: 22).
  --disable-root      Desabilita login de root por SSH (após testar o novo user).
EOF
}

# ---- Parse args ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user) NEW_USER="${2:-}"; shift 2;;
    --pubkey) PUBKEY_CONTENT="${2:-}"; shift 2;;
    --pubkey-file) PUBKEY_FILE="${2:-}"; shift 2;;
    --ssh-port) SSH_PORT="${2:-}"; shift 2;;
    --disable-root) DISABLE_ROOT="yes"; shift 1;;
    -h|--help) usage; exit 0;;
    *) err "Arg desconhecido: $1"; usage; exit 1;;
  esac
done

# ---- Root check ----
if [[ "$EUID" -ne 0 ]]; then
  err "Rode como root (use sudo)."; exit 1
fi

# ---- Distro check (best effort) ----
if [[ -r /etc/os-release ]]; then . /etc/os-release; fi

# ---- Resolve chave pública ----
if [[ -n "$PUBKEY_FILE" && -z "$PUBKEY_CONTENT" ]]; then
  if [[ -f "$PUBKEY_FILE" ]]; then
    PUBKEY_CONTENT="$(tr -d '\r' < "$PUBKEY_FILE")"
  else
    err "Arquivo de chave pública não encontrado: $PUBKEY_FILE"; exit 1
  fi
fi

if [[ -z "$PUBKEY_CONTENT" ]]; then
  if [[ -f /root/.ssh/authorized_keys ]]; then
    warn "Nenhuma --pubkey/--pubkey-file informada; vou manter authorized_keys do root."
  else
    err "Nenhuma chave pública fornecida e root não tem authorized_keys. Use --pubkey ou --pubkey-file."; exit 1
  fi
fi

# ---- Pacotes ----
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  openssh-server ufw fail2ban unattended-upgrades ca-certificates
log "Pacotes instalados."

# ---- Cria usuário sudo (opcional) ----
if [[ -n "$NEW_USER" ]]; then
  if id "$NEW_USER" &>/dev/null; then
    warn "Usuário $NEW_USER já existe, seguindo."
  else
    adduser --disabled-password --gecos "" "$NEW_USER"
    usermod -aG sudo "$NEW_USER"
    passwd -l "$NEW_USER" >/dev/null 2>&1 || true
    log "Usuário $NEW_USER criado e adicionado ao grupo sudo."
  fi
  install -d -m 700 "/home/$NEW_USER/.ssh"
  if [[ -n "$PUBKEY_CONTENT" ]]; then
    echo "$PUBKEY_CONTENT" > "/home/$NEW_USER/.ssh/authorized_keys"
  fi
  chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"
  chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"
  log "Chave pública instalada em /home/$NEW_USER/.ssh/authorized_keys"
fi

# ---- Garante chave no root (failsafe) ----
if [[ -n "$PUBKEY_CONTENT" ]]; then
  install -d -m 700 /root/.ssh
  touch /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
  if ! grep -qF "$PUBKEY_CONTENT" /root/.ssh/authorized_keys; then
    echo "$PUBKEY_CONTENT" >> /root/.ssh/authorized_keys
  fi
  log "Chave também garantida em /root/.ssh/authorized_keys (failsafe)."
fi

# ---- Detecta unit do OpenSSH (Ubuntu=ssh / Debian=sshd) ----
SSH_UNIT="ssh"
if systemctl list-unit-files | grep -q '^ssh.service'; then
  SSH_UNIT="ssh"
elif systemctl list-unit-files | grep -q '^sshd.service'; then
  SSH_UNIT="sshd"
else
  # fallback: tenta status para decidir
  if systemctl status ssh >/dev/null 2>&1; then SSH_UNIT="ssh"; else SSH_UNIT="sshd"; fi
fi
log "Unit do OpenSSH detectada: $SSH_UNIT.service"

# ---- SSH hardening ----
SSHD_CFG="/etc/ssh/sshd_config"
cp -a "$SSHD_CFG" "${SSHD_CFG}.bak.$(date +%F_%T)"

# Normaliza diretivas
sed -i \
  -e 's/^#\?\s*PubkeyAuthentication.*/PubkeyAuthentication yes/' \
  -e 's/^#\?\s*PasswordAuthentication.*/PasswordAuthentication no/' \
  -e 's/^#\?\s*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' \
  -e 's/^#\?\s*UsePAM.*/UsePAM yes/' \
  -e 's/^#\?\s*PermitRootLogin.*/PermitRootLogin prohibit-password/' \
  -e 's|^#\?\s*AuthorizedKeysFile.*|AuthorizedKeysFile .ssh/authorized_keys|' \
  "$SSHD_CFG"

# Porta customizada
if [[ "$SSH_PORT" != "22" ]]; then
  if grep -qE '^\s*Port\s+' "$SSHD_CFG"; then
    sed -i "s|^\s*Port\s\+.*|Port ${SSH_PORT}|" "$SSHD_CFG"
  else
    echo "Port ${SSH_PORT}" >> "$SSHD_CFG"
  fi
fi

# Desabilita root completamente, se pedido
if [[ "$DISABLE_ROOT" == "yes" ]]; then
  sed -i 's/^PermitRootLogin .*/PermitRootLogin no/' "$SSHD_CFG"
fi

# Testa configuração do sshd antes de aplicar
SSHD_BIN="$(command -v sshd || true)"
if [[ -z "$SSHD_BIN" ]]; then
  # caminhos comuns
  for p in /usr/sbin/sshd /usr/local/sbin/sshd; do
    [[ -x "$p" ]] && SSHD_BIN="$p" && break
  done
fi

if [[ -x "$SSHD_BIN" ]]; then
  if ! "$SSHD_BIN" -t; then
    err "Config do SSH inválida. Restaurando backup."
    cp -a "${SSHD_CFG}.bak."* "$SSHD_CFG"
    systemctl restart "$SSH_UNIT" || true
    exit 1
  fi
else
  warn "Não encontrei binário do sshd para validar config; seguindo assim mesmo."
fi

systemctl restart "$SSH_UNIT"
log "OpenSSH reiniciado com sucesso ($SSH_UNIT)."

# ---- Firewall (UFW) ----
ufw --force reset >/dev/null 2>&1 || true
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp" comment 'ssh'
ufw limit "${SSH_PORT}/tcp" || true
# Exemplos web (descomente se necessário)
# ufw allow 80/tcp comment 'http'
# ufw allow 443/tcp comment 'https'
ufw --force enable
log "UFW habilitado. Porta SSH ${SSH_PORT} liberada e com rate-limit."

# ---- Fail2ban básico para sshd ----
mkdir -p /etc/fail2ban/jail.d
cat >/etc/fail2ban/jail.d/sshd.local <<JAIL
[sshd]
enabled = true
port    = ${SSH_PORT}
filter  = sshd
logpath = %(sshd_log)s
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
bantime.increment = true
bantime.factor = 1.5
bantime.maxtime = 24h
JAIL

systemctl enable --now fail2ban
log "Fail2ban configurado e iniciado."

# ---- Updates automáticos ----
cat >/etc/apt/apt.conf.d/20auto-upgrades <<'AUTO'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
AUTO

apt-get install -y unattended-upgrades >/dev/null 2>&1 || true
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive unattended-upgrades || true
log "Unattended-upgrades ativado."

# ---- Resumo ----
echo
log "Endurecimento concluído!"
echo "Resumo:"
echo " - SSH somente por chave (PasswordAuthentication no)."
if [[ "$DISABLE_ROOT" == "yes" ]]; then
  echo " - Login de root via SSH: DESABILITADO."
else
  echo " - Login de root via SSH: permitido só por chave (prohibit-password)."
fi
echo " - Porta SSH: ${SSH_PORT}"
[[ -n "$NEW_USER" ]] && echo " - Usuário sudo criado: ${NEW_USER}"
echo " - UFW ativo; inbound negado por padrão; SSH liberado e rate-limited."
echo " - Fail2ban ativo para sshd (ban progressivo)."
echo " - Updates automáticos habilitados."
echo
echo "Teste de conexão em outro terminal ANTES de sair desta sessão:"
if [[ "$SSH_PORT" == "22" ]]; then
  echo "  ssh -i ~/.ssh/id_ed25519 ${NEW_USER:-root}@SEU_IP"
else
  echo "  ssh -p ${SSH_PORT} -i ~/.ssh/id_ed25519 ${NEW_USER:-root}@SEU_IP"
fi
