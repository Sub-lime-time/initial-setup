#!/bin/bash
# Certificate Distribution Script
# Distributes SSL certificates to system and service locations.
# Intended to be idempotent and safe to re-run.
# Usage: sudo ./distribute-certs.sh

set -euo pipefail

CERT_SRC="/mnt/linux/certs/letsencrypt"
CERT_DEST="/etc/ssl/certs"
KEY_DEST="/etc/ssl/private"
LOG_FILE="/var/log/cert-distribution.log"

log() { echo "[$(date)] $*" | tee -a "$LOG_FILE"; }
error() { log "ERROR: $*"; exit 1; }

DN=$(hostname -d)
HOSTNAME=$(hostname -f)

log "Starting certificate distribution for $HOSTNAME ($DN)"

ensure_cert_source() {
    if [ ! -d "$CERT_SRC" ]; then
        ls -la "${CERT_SRC%/*}" > /dev/null 2>&1
        sleep 1
        [ ! -d "$CERT_SRC" ] && error "Cannot access certificate source directory $CERT_SRC. Check autofs/NFS."
    fi
}

copy_base_certs() {
    if [ ! -f "$CERT_SRC/$DN.crt" ] || [ ! -f "$CERT_SRC/$DN.key" ]; then
        error "Certificates for $DN not found in $CERT_SRC!"
    fi

    if ! openssl x509 -checkend 86400 -noout -in "$CERT_SRC/$DN.crt"; then
        log "WARNING: Certificate for $DN is expired or will expire soon!"
    fi

    sudo mkdir -p "$CERT_DEST" "$KEY_DEST"
    CERT_CHANGED=0
    if ! cmp -s "$CERT_SRC/$DN.crt" "$CERT_DEST/$DN.crt" || ! cmp -s "$CERT_SRC/$DN.key" "$KEY_DEST/$DN.key"; then
        CERT_CHANGED=1
        log "New certificates detected. Updating base certs..."
        sudo cp "$CERT_SRC/$DN.crt" "$CERT_DEST/"
        sudo cp "$CERT_SRC/$DN.key" "$KEY_DEST/"
        sudo chmod 644 "$CERT_DEST/$DN.crt"
        sudo chmod 600 "$KEY_DEST/$DN.key"
        sudo chown root:root "$CERT_DEST/$DN.crt" "$KEY_DEST/$DN.key"
        sudo chgrp www-data "$KEY_DEST/$DN.key"
        sudo chmod 640 "$KEY_DEST/$DN.key"
        log "Base certificates updated successfully."
    else
        log "No certificate updates needed for base system."
    fi
    return $CERT_CHANGED
}

update_apache() {
    if systemctl list-units --full -all | grep -Fq "apache2.service"; then
        log "Configuring certificates for Apache..."
        sudo mkdir -p /etc/apache2/ssl
        sudo ln -sf "$CERT_DEST/$DN.crt" "/etc/apache2/ssl/$DN.crt"
        sudo ln -sf "$KEY_DEST/$DN.key" "/etc/apache2/ssl/$DN.key"
        log "Restarting Apache..."
        sudo systemctl restart apache2
    fi
}

update_nginx() {
    if systemctl list-units --full -all | grep -Fq "nginx.service"; then
        log "Configuring certificates for Nginx..."
        sudo mkdir -p /etc/nginx/ssl
        sudo ln -sf "$CERT_DEST/$DN.crt" "/etc/nginx/ssl/$DN.crt"
        sudo ln -sf "$KEY_DEST/$DN.key" "/etc/nginx/ssl/$DN.key"
        log "Restarting Nginx..."
        sudo systemctl restart nginx
    fi
}

update_docker() {
    if command -v docker &> /dev/null; then
        log "Checking for Docker services that need certificate updates..."
        if docker ps -a --format '{{.Names}}' | grep -q "^portainer$"; then
            log "Restarting Portainer..."
            docker restart portainer
        fi
    fi
}

update_wazuh() {
    if systemctl list-units --full -all | grep -Fq "wazuh-manager.service"; then
        log "Configuring certificates for Wazuh..."
        WAZUH_ETC_DIR="/var/ossec/etc"
        WAZUH_API_SSL_DIR="/var/ossec/api/configuration/ssl"
        WAZUH_API_CONFIG="/var/ossec/api/configuration/api.yaml"
        WAZUH_DASHBOARD_CERT_DIR="/usr/share/wazuh-dashboard/certs"

        sudo mkdir -p "$WAZUH_ETC_DIR" "$WAZUH_API_SSL_DIR"
        sudo cp "$CERT_DEST/$DN.crt" "$WAZUH_ETC_DIR/"
        sudo cp "$KEY_DEST/$DN.key" "$WAZUH_ETC_DIR/"
        sudo chown wazuh:wazuh "$WAZUH_ETC_DIR/$DN.crt" "$WAZUH_ETC_DIR/$DN.key"
        sudo chmod 644 "$WAZUH_ETC_DIR/$DN.crt"
        sudo chmod 640 "$WAZUH_ETC_DIR/$DN.key"

        sudo cp "$CERT_DEST/$DN.crt" "$WAZUH_API_SSL_DIR/server.crt"
        sudo cp "$KEY_DEST/$DN.key" "$WAZUH_API_SSL_DIR/server.key"
        sudo chown wazuh:wazuh "$WAZUH_API_SSL_DIR/server.crt" "$WAZUH_API_SSL_DIR/server.key"
        sudo chmod 644 "$WAZUH_API_SSL_DIR/server.crt"
        sudo chmod 640 "$WAZUH_API_SSL_DIR/server.key"

        if [ -d "/usr/share/wazuh-dashboard" ]; then
            sudo mkdir -p "$WAZUH_DASHBOARD_CERT_DIR"
            sudo cp "$CERT_DEST/$DN.crt" "$WAZUH_DASHBOARD_CERT_DIR/dashboard.crt"
            sudo cp "$KEY_DEST/$DN.key" "$WAZUH_DASHBOARD_CERT_DIR/dashboard.key"
            if getent passwd wazuh-dashboard > /dev/null 2>&1; then
                sudo chown wazuh-dashboard:wazuh-dashboard "$WAZUH_DASHBOARD_CERT_DIR/dashboard.crt" "$WAZUH_DASHBOARD_CERT_DIR/dashboard.key"
            else
                sudo chown wazuh:wazuh "$WAZUH_DASHBOARD_CERT_DIR/dashboard.crt" "$WAZUH_DASHBOARD_CERT_DIR/dashboard.key"
            fi
            sudo chmod 644 "$WAZUH_DASHBOARD_CERT_DIR/dashboard.crt"
            sudo chmod 640 "$WAZUH_DASHBOARD_CERT_DIR/dashboard.key"
        fi

        # (Retain your Wazuh API config and restart logic here, as in your original script)
        # For brevity, not repeating the full Wazuh config update logic here.
    fi
}

main() {
    ensure_cert_source
    copy_base_certs
    update_apache
    update_nginx
    update_docker
    update_wazuh
    log "Certificate distribution completed successfully."
}

main "$@"
