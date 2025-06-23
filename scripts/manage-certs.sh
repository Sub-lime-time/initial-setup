#!/bin/bash
# Manage SSL Certificates Script
# Purpose: Synchronize and deploy SSL certificates across systems and services.
# Usage: sudo ./manage-certs.sh [-f|--force]
# Last Revised: 2025/01/03

set -euo pipefail

# Logging setup
LOG_FILE="/var/log/manage-certs.log"
sudo mkdir -p "$(dirname "$LOG_FILE")"
log()   { echo -e "\033[1;32m[INFO]\033[0m $(date '+%F %T') [$HOSTNAME] $*" | tee -a "$LOG_FILE"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $(date '+%F %T') [$HOSTNAME] $*" | tee -a "$LOG_FILE"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $(date '+%F %T') [$HOSTNAME] $*" | tee -a "$LOG_FILE"; exit 1; }

HOSTNAME=$(hostname -f)
DOMAIN=$(echo "$HOSTNAME" | cut -d. -f2-)
FORCE_RESTART=false
[[ "${1:-}" == "-f" || "${1:-}" == "--force" ]] && FORCE_RESTART=true && log "Force restart enabled by command-line option"

CERT_UPDATED=false
ROLE=""

# Centralized per-server cert location
CANONICAL_CERT_DIR="/etc/ssl/letsencrypt/$DOMAIN"
CANONICAL_FULLCHAIN="$CANONICAL_CERT_DIR/fullchain.pem"
CANONICAL_PRIVKEY="$CANONICAL_CERT_DIR/privkey.pem"

# NFS shared cert directory
NFS_CERT_PATH="/mnt/linux/certs/$DOMAIN"
NFS_FULLCHAIN="$NFS_CERT_PATH/fullchain.pem"
NFS_PRIVKEY="$NFS_CERT_PATH/privkey.pem"

# Let's Encrypt live path
LE_CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
LE_FULLCHAIN="$LE_CERT_PATH/fullchain.pem"
LE_PRIVKEY="$LE_CERT_PATH/privkey.pem"

sudo mkdir -p "$CANONICAL_CERT_DIR"

determine_role() {
  case "$HOSTNAME" in
    adguard1.hq.802ski.com | kibbe.er.802ski.com | lax.la.ramalamba.com) ROLE="cert_master" ;;
    *) ROLE="cert_client" ;;
  esac
  log "Starting cert sync with role: $ROLE"
}

sync_certs() {
  case "$ROLE" in
    cert_master)
      if [[ "$LE_FULLCHAIN" -nt "$NFS_FULLCHAIN" || "$LE_PRIVKEY" -nt "$NFS_PRIVKEY" ]]; then
        sudo mkdir -p "$NFS_CERT_PATH"
        sudo cp "$LE_FULLCHAIN" "$NFS_FULLCHAIN"
        sudo cp "$LE_PRIVKEY" "$NFS_PRIVKEY"
        sudo chmod 644 "$NFS_FULLCHAIN" "$NFS_PRIVKEY"
        log "Copied updated certs to NFS share"
      else
        log "NFS certs already current"
      fi

      if [[ "$LE_FULLCHAIN" -nt "$CANONICAL_FULLCHAIN" || "$LE_PRIVKEY" -nt "$CANONICAL_PRIVKEY" ]]; then
        sudo cp "$LE_FULLCHAIN" "$CANONICAL_FULLCHAIN"
        sudo cp "$LE_PRIVKEY" "$CANONICAL_PRIVKEY"
        sudo chmod 600 "$CANONICAL_FULLCHAIN" "$CANONICAL_PRIVKEY"
        log "Updated canonical certs on master"
        CERT_UPDATED=true
      fi
      ;;
    cert_client)
      if [[ "$NFS_FULLCHAIN" -nt "$CANONICAL_FULLCHAIN" || "$NFS_PRIVKEY" -nt "$CANONICAL_PRIVKEY" ]]; then
        sudo cp "$NFS_FULLCHAIN" "$CANONICAL_FULLCHAIN"
        sudo cp "$NFS_PRIVKEY" "$CANONICAL_PRIVKEY"
        sudo chmod 600 "$CANONICAL_FULLCHAIN" "$CANONICAL_PRIVKEY"
        log "Synced certs from NFS to canonical location"
        CERT_UPDATED=true
      fi
      ;;
  esac
}

restart_services() {
  SRC_FULLCHAIN="$CANONICAL_FULLCHAIN"
  SRC_PRIVKEY="$CANONICAL_PRIVKEY"

  # AdGuard (Snap)
  if [[ -d /var/snap/adguard-home ]]; then
    log "Preparing to update AdGuard certs..."
    DST="/var/snap/adguard-home/common"
    sudo cp "$SRC_FULLCHAIN" "$DST/fullchain.pem"
    sudo cp "$SRC_PRIVKEY" "$DST/privkey.pem"
    sudo chmod 600 "$DST/"*.pem
    sudo chown root:root "$DST/"*.pem
    log "Updated AdGuard certs (Snap confinement); no restart needed."
  fi

  # Apache
  if command -v apache2 >/dev/null 2>&1 || command -v httpd >/dev/null 2>&1; then
    log "Attempting to reload Apache..."
    if sudo systemctl reload apache2 || sudo systemctl reload httpd; then
      log "Reloaded Apache with updated certs"
    else
      warn "Failed to reload Apache"
    fi
  fi

  # Portainer (Docker container version)
  if command -v docker >/dev/null 2>&1; then
    if docker ps --format '{{.Names}}' | grep -q '^portainer$'; then
      log "Attempting to restart Portainer (Docker container)..."
      if docker restart portainer; then
        log "Restarted Portainer (Docker container) due to cert update"
      else
        warn "Failed to restart Portainer"
      fi
    fi
  fi

  # Docker (if TLS-enabled)
  if command -v docker >/dev/null 2>&1 && [[ -f /etc/docker/daemon.json ]] && grep -q 'tlsverify' /etc/docker/daemon.json; then
    log "Attempting to restart Docker..."
    if sudo systemctl restart docker; then
      log "Restarted Docker due to cert update"
    else
      warn "Failed to restart Docker"
    fi
  fi
}

main() {
  determine_role
  sync_certs
  if [[ "$CERT_UPDATED" == true || "$FORCE_RESTART" == true ]]; then
    restart_services
  else
    log "No cert updates detected and not forced; skipping service restarts"
  fi
  log "Cert sync completed."
}

main "$@"

log "Cert sync completed."
