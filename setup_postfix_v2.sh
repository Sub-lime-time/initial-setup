#!/bin/bash
# Postfix Setup Script (idempotent, interactive)
# Installs and configures Postfix for sending mail only (no local delivery)

set -euo pipefail

log() { echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*"; exit 1; }

# Preseed debconf answers for non-interactive install
log "Pre-seeding Postfix configuration for 'Internet Site'..."
echo "postfix postfix/mailname string $(hostname --fqdn)" | sudo debconf-set-selections
echo "postfix postfix/main_mailer_type string 'Internet Site'" | sudo debconf-set-selections

# Install Postfix if not already installed
if ! dpkg -l | grep -q '^ii  postfix '; then
    log "Installing Postfix..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postfix
else
    log "Postfix is already installed. Skipping installation."
fi

# Optionally, configure /etc/postfix/main.cf or other settings here
# Example: set relayhost (uncomment and edit as needed)
# sudo postconf -e "relayhost = [smtp.example.com]:587"
# sudo postconf -e "smtp_use_tls = yes"

# Restart Postfix to apply any changes
log "Restarting Postfix..."
sudo systemctl restart postfix

log "Postfix setup complete." 