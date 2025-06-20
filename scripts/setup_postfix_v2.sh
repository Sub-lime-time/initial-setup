#!/bin/bash
set -euo pipefail

# --- Configurable Variables ---
CREDENTIALS_FILE="${CREDENTIALS_FILE:-/mnt/linux/postfix/sasl_passwd}"
CUSTOM_ALIASES_FILE="${CUSTOM_ALIASES_FILE:-/mnt/linux/postfix/aliases}"
POSTFIX_SASL_FILE="/etc/postfix/sasl_passwd"
SENDER_CANONICAL_FILE="/etc/postfix/sender_canonical"
GENERIC_FILE="/etc/postfix/generic"
MAIN_CF="/etc/postfix/main.cf"
LOG_FILE="${LOG_FILE:-$HOME/setup_postfix_v2.log}"
TEST_EMAIL_RECIPIENT="${TEST_EMAIL_RECIPIENT:-postmaster}"

# --- Logging Function ---
log() {
    local level="$1"; shift
    local msg="$*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $msg" | tee -a "$LOG_FILE"
}

# --- Extract FQDN, SITE_ID, DOMAIN ---
FQDN=$(hostname -f)
SITE_ID=$(echo "$FQDN" | awk -F. '{print $2}')
DOMAIN=$(hostname -d | rev | cut -d'.' -f1,2 | rev)
SHORT_HOSTNAME=$(hostname)

if [[ -z "$SITE_ID" || -z "$DOMAIN" ]]; then
    log ERROR "Unable to extract site_id or domain from FQDN ($FQDN)"
    exit 1
fi
log INFO "Extracted site_id: $SITE_ID"
log INFO "Extracted domain: $DOMAIN"

# Use FQDN as the display name
SENDER_DISPLAY_NAME="$FQDN"

# --- Preconfigure and Install Postfix ---
if ! dpkg -l | grep -q postfix; then
    log INFO "Installing Postfix and dependencies..."
    echo "postfix postfix/mailname string $FQDN" | sudo debconf-set-selections
    echo "postfix postfix/main_mailer_type select Internet Site" | sudo debconf-set-selections
    sudo apt-get update | tee -a "$LOG_FILE"
    sudo apt-get install -y mailutils libsasl2-modules postfix | tee -a "$LOG_FILE"
else
    log INFO "Postfix already installed. Skipping installation."
fi

# --- Copy credentials (idempotent) ---
if [[ ! -f "$CREDENTIALS_FILE" ]]; then
    log ERROR "Credentials file not found at $CREDENTIALS_FILE"
    exit 1
fi
if ! cmp -s "$CREDENTIALS_FILE" "$POSTFIX_SASL_FILE" 2>/dev/null; then
    log INFO "Copying credentials file to Postfix directory"
    sudo cp "$CREDENTIALS_FILE" "$POSTFIX_SASL_FILE"
    sudo chmod 600 "$POSTFIX_SASL_FILE"
    sudo postmap "$POSTFIX_SASL_FILE"
else
    log INFO "Credentials file already up to date."
fi

# --- Configure sender canonical and generic maps (idempotent) ---
SENDER_LINE="/.*/ \"$SENDER_DISPLAY_NAME\" <linux@$DOMAIN>"
if [[ ! -f "$SENDER_CANONICAL_FILE" ]] || ! grep -Fxq "$SENDER_LINE" "$SENDER_CANONICAL_FILE"; then
    log INFO "Configuring sender_canonical_maps"
    echo "$SENDER_LINE" | sudo tee "$SENDER_CANONICAL_FILE" > /dev/null
    sudo postmap "$SENDER_CANONICAL_FILE"
else
    log INFO "sender_canonical_maps already configured."
fi
if [[ ! -f "$GENERIC_FILE" ]] || ! grep -Fxq "$SENDER_LINE" "$GENERIC_FILE"; then
    log INFO "Configuring smtp_generic_maps for sender display name"
    echo "$SENDER_LINE" | sudo tee "$GENERIC_FILE" > /dev/null
    sudo postmap "$GENERIC_FILE"
else
    log INFO "smtp_generic_maps already configured."
fi

# --- Copy aliases if present (idempotent) ---
if [[ -f "$CUSTOM_ALIASES_FILE" ]]; then
    if ! cmp -s "$CUSTOM_ALIASES_FILE" /etc/aliases 2>/dev/null; then
        log INFO "Copying custom aliases file to /etc/aliases"
        sudo cp "$CUSTOM_ALIASES_FILE" /etc/aliases
        sudo newaliases
    else
        log INFO "Custom aliases file already up to date."
    fi
else
    log INFO "Custom aliases file not found at $CUSTOM_ALIASES_FILE"
fi

# --- Write main.cf (idempotent, with backup) ---
MAIN_CF_CONTENT="# Basic settings\nmyhostname = $FQDN\nmyorigin = 802ski.com\nmydestination = \$myhostname, localhost.\$mydomain, localhost\nmasquerade_domains = $DOMAIN\nmynetworks = 127.0.0.0/8 [::1]/128\nappend_dot_mydomain = no\ncompatibility_level = 2\n\n# Relay settings\nrelayhost = [smtp.fastmail.com]:587\nsmtp_use_tls = yes\nsmtp_tls_security_level = encrypt\nsmtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt\nsmtp_sasl_auth_enable = yes\nsmtp_sasl_security_options =\nsmtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd\n\n# Canonical mapping for sender addresses\nsender_canonical_maps = regexp:/etc/postfix/sender_canonical\nsmtp_generic_maps = hash:/etc/postfix/generic\n"
if [[ ! -f "$MAIN_CF" ]] || [[ "$(sudo cat "$MAIN_CF")" != "$MAIN_CF_CONTENT" ]]; then
    log INFO "Backing up and writing new main.cf"
    sudo cp "$MAIN_CF" "${MAIN_CF}.bak.$(date +%s)" 2>/dev/null || true
    echo -e "$MAIN_CF_CONTENT" | sudo tee "$MAIN_CF" > /dev/null
else
    log INFO "main.cf already up to date."
fi

# --- Restart Postfix ---
log INFO "Restarting Postfix"
sudo systemctl restart postfix | tee -a "$LOG_FILE"

# --- Test email ---
log INFO "Sending test email to $TEST_EMAIL_RECIPIENT and logging headers for verification"
/usr/sbin/sendmail -t <<EOF
From: "$FQDN" <linux@$DOMAIN>
To: $TEST_EMAIL_RECIPIENT
Subject: Test Email

Test email body
EOF

# Log the most recent mail in the mail spool (if available)
MAIL_LOG_FILE="$HOME/mbox"
if [[ -f "$MAIL_LOG_FILE" ]]; then
    log INFO "Logging last message headers from $MAIL_LOG_FILE for verification:"
    awk '/^From /{f=0} {if(f)print} /^From /{f=1}' "$MAIL_LOG_FILE" | head -20 | tee -a "$LOG_FILE"
else
    log INFO "Mail spool file $MAIL_LOG_FILE not found; cannot log headers."
fi

log INFO "Postfix setup complete!"
