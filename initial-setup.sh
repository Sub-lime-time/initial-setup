#!/bin/bash
# Ubuntu Initial Setup Script (Interactive)
# Usage: sudo ./initial-setup.sh
# Purpose: Automates initial configuration on new Ubuntu installs
#          This script is intended to be run interactively and will prompt for user input where needed.
# Last Revised: 2025/01/03

set -euo pipefail


SHORT_DELAY=2
LONG_DELAY=5

log() { echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERROR]\033[0m $*"; exit 1; }

update_bashrc() {
    log "Updating BASH"
sleep $SHORT_DELAY
    if ! grep -q "$(dirname "$0")/scripts" ~/.bashrc; then
        echo "export PATH=\$PATH:$(dirname "$0")/scripts" >> ~/.bashrc
fi
source ~/.bashrc
}

setup_hosts_file() {
    log "Setting up /etc/hosts entries..."
    
    # Backup current hosts file
    sudo cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S)
    
    # Get current hostname
    current_hostname=$(hostname)
    
    # Get the primary LAN IP using default gateway
    default_gateway=$(ip route | grep default | awk '{print $3}')
    log "Detected default gateway: $default_gateway"
    if [[ -n "$default_gateway" ]]; then
        lan_ip=$(ip route get "$default_gateway" | awk '/src/ {for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}')
        if [[ -z "$lan_ip" ]]; then
            lan_ip=$(ip route get "$default_gateway" | awk '{print $7; exit}')
        fi
    else
        lan_ip=""
    fi
    log "Detected LAN IP: $lan_ip"
    
    if [[ -n "$lan_ip" && "$lan_ip" != "127.0.0.1" ]]; then
        # Extract subnet for mapping
        if [[ "$lan_ip" =~ ^10\.([0-9]+)\. ]]; then
            subnet="10.${BASH_REMATCH[1]}"
        else
            subnet=$(echo "$lan_ip" | awk -F. '{print $1 "." $2 "." $3}')
        fi
        # Subnet to domain mapping
        case "$subnet" in
            10.7)
                domain_name="hq.802ski.com" ;;
            10.8)
                domain_name="er.802ski.com" ;;
            192.168.50)
                domain_name="la.ramalamba.com" ;;
            192.168.11)
                domain_name="nj.zoinks.us" ;;
            192.168.7)
                domain_name="hq.802ski.com" ;;
            192.168.8)
                domain_name="er.802ski.com" ;;
            *)
                domain_name="local" ;;
        esac
        fqdn="${current_hostname}.${domain_name}"
        # Remove any existing entry for this IP
        sudo sed -i "/^${lan_ip}[[:space:]]/d" /etc/hosts
        # Add new entry with LAN IP
        echo "$lan_ip $fqdn $current_hostname" | sudo tee -a /etc/hosts
        log "Updated /etc/hosts: $lan_ip $fqdn $current_hostname"
        # Ensure 127.0.1.1 line is present and correct
        if grep -q '^127.0.1.1' /etc/hosts; then
            sudo sed -i "s|^127.0.1.1.*|127.0.1.1 $fqdn $current_hostname|" /etc/hosts
            log "Updated 127.0.1.1 entry: 127.0.1.1 $fqdn $current_hostname"
        else
            echo "127.0.1.1 $fqdn $current_hostname" | sudo tee -a /etc/hosts
            log "Added 127.0.1.1 entry: 127.0.1.1 $fqdn $current_hostname"
        fi
        echo "================================================"
        echo "\nCurrent /etc/hosts entry for this IP:" 
        grep "^${lan_ip}[[:space:]]" /etc/hosts
        echo "================================================"
        echo "Current /etc/hosts entry for 127.0.1.1:" 
        echo "================================================"
        grep "^127.0.1.1[[:space:]]" /etc/hosts
        echo "================================================"
        echo "Press Enter to continue, or Ctrl+C to abort..."
        read -p "Does this look correct?"
    else
        warn "Could not determine LAN IP. Skipping /etc/hosts update."
    fi
}

set_timezone() {
    log "Setting timezone to America/New_York..."
sleep $SHORT_DELAY
sudo timedatectl set-timezone America/New_York
    log "Current timezone: $(timedatectl | grep 'Time zone')"
}

install_packages() {
    log "Installing base packages..."
sleep $SHORT_DELAY
    sudo apt-get update && sudo NEEDRESTART_MODE=a apt-get dist-upgrade -y
    sudo NEEDRESTART_MODE=a apt-get -y install \
    nfs-common ntp cifs-utils ncdu lsof strace sysstat iotop \
    mtr nmap dnsutils jq \
    smbclient apt-transport-https ca-certificates curl software-properties-common \
    micro net-tools smartmontools || error "Error installing base packages. Exiting."
sleep $SHORT_DELAY
echo "iperf3 iperf3/start_autostart boolean true" | sudo debconf-set-selections
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iperf3
}

install_1password() {
    log "Installing 1Password CLI..."
    sleep $SHORT_DELAY
    # Official 1Password CLI install script with debsig policy and architecture awareness
    curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
      sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg && \
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
      sudo tee /etc/apt/sources.list.d/1password.list && \
      sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22/ && \
      curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol | \
      sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol && \
      sudo mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22 && \
      curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
      sudo gpg --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg && \
      sudo apt update && sudo apt install -y 1password-cli
    if command -v op &> /dev/null; then
        log "1Password CLI installed successfully."
    else
        error "1Password CLI installation failed."
    fi
}

setup_virtualization_tools() {
virt=$(systemd-detect-virt)
if [ "$virt" = "microsoft" ]; then
        log "Detected Microsoft Hyper-V. Installing virtualization tools..."
        sudo NEEDRESTART_MODE=a apt-get -y install linux-virtual linux-cloud-tools-virtual linux-tools-virtual
elif [ "$virt" = "kvmq" ]; then
        log "Detected KVM/QEMU. Installing virtualization tools..."
        sudo NEEDRESTART_MODE=a apt-get -y install qemu-guest-agent
    sudo systemctl enable qemu-guest-agent
else
        log "No specific virtualization tools required for $virt."
fi
}

install_glances() {
    log "Installing Glances for system monitoring..."
sleep $SHORT_DELAY
    sudo snap install glances || error "Failed to install Glances."
}

setup_autofs() {
    log "Setting up AUTOFS for NFS mounts..."
    sleep $SHORT_DELAY
    sudo NEEDRESTART_MODE=a apt-get -y install autofs
    
    # Copy autofs configuration files
    if [ -f "$(dirname "$0")/configs/etc/autofs/auto.master" ]; then
        sudo cp "$(dirname "$0")/configs/etc/autofs/auto.master" /etc/auto.master
        sudo cp "$(dirname "$0")/configs/etc/autofs/auto.nfs" /etc/auto.nfs
        sudo chmod 644 /etc/auto.master /etc/auto.nfs
        log "Autofs configuration files copied successfully."
    else
        warn "Autofs config files not found in configs/etc/autofs/. Skipping autofs setup."
        return
    fi
    
    sudo systemctl restart autofs
}

setup_samba() {
    log "Setting up SAMBA..."
    sleep $SHORT_DELAY

    # Install Samba packages from official Ubuntu repo
    log "Installing Samba packages..."
    sudo NEEDRESTART_MODE=a apt-get -y install samba samba-common-bin || error "Error installing Samba packages. Exiting."

    # Copy Samba configuration files
    if [ -f "$(dirname "$0")/configs/etc/samba/smb.conf" ]; then
        sudo cp "$(dirname "$0")/configs/etc/samba/smb.conf" /etc/samba/smb.conf
        sudo chmod 644 /etc/samba/smb.conf
        log "Samba configuration file copied successfully."
    else
        warn "Samba config file not found in configs/etc/samba/. Using default configuration."
    fi

    # Retrieve or generate unique Samba password for this host from 1Password
    SAMBA_ITEM="samba-$(hostname)"
    if command -v op &> /dev/null; then
        if op item get "$SAMBA_ITEM" --vault=Private --fields label=password &>/dev/null; then
            SAMBA_PASSWORD=$(op read "op://Private/$SAMBA_ITEM/password")
            log "Samba password for $SAMBA_ITEM retrieved from 1Password."
        else
            op item create --category=login --vault=Private --title="$SAMBA_ITEM" username="greg" --generate-password -tags samba,homelab > /dev/null
            SAMBA_PASSWORD=$(op read "op://Private/$SAMBA_ITEM/password")
            log "Generated and stored new Samba password for $SAMBA_ITEM in 1Password."
        fi
    else
        read -s -p "Enter Samba password for user 'greg': " SAMBA_PASSWORD
        echo
    fi
    export SAMBA_PASSWORD

    # Enable and start Samba services
    log "Enabling and starting Samba services..."
    sudo systemctl enable smbd nmbd
    sudo systemctl restart smbd nmbd

    log "Samba setup complete."
}

setup_github_ssh_key_from_server() {
    log "Fetching GitHub SSH key from 1Password CLI..."
    if command -v op &> /dev/null; then
        # Fetch private key
        op read "op://Private/id_ed25519_github/private key" > ~/.ssh/github
        chmod 600 ~/.ssh/github
        # Write public key
        echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH7vspSV++pdVro1MbLaHuHZFbMWA27DG70iKKtXyLf0" > ~/.ssh/github.pub
        chmod 644 ~/.ssh/github.pub
        log "GitHub SSH key fetched from 1Password and installed."
    else
        warn "1Password CLI (op) not found. Skipping GitHub SSH key setup."
    fi
}

setup_ssh_github() {
    log "Setting up SSH for GitHub..."
sleep $SHORT_DELAY

    # Create .ssh directory if it doesn't exist
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    
    # Import GitHub SSH keys
    if command -v curl &> /dev/null; then
        log "Importing SSH keys from GitHub for Sub-lime-time..."
        curl -fsSL "https://github.com/Sub-lime-time.keys" | tee -a ~/.ssh/authorized_keys
        chmod 600 ~/.ssh/authorized_keys
        log "GitHub SSH keys imported successfully."
    else
        warn "curl not available. Skipping GitHub key import."
    fi
    
    # Copy any additional SSH config from local configs
    if [ -d "$(dirname "$0")/configs/ssh" ]; then
        cp -r "$(dirname "$0")/configs/ssh/"* ~/.ssh/
    chmod 600 ~/.ssh/*
else
        warn "SSH config directory not found. Skipping..."
fi

    # In your script, check if the file exists before copying
    if [ -f "$(dirname "$0")/configs/ssh/github" ]; then
        cp "$(dirname "$0")/configs/ssh/github" ~/.ssh/
    fi
}

setup_ssh_hardening() {
    log "Hardening SSH configuration..."
    sleep $SHORT_DELAY
    # Disable password authentication
    sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    log "SSH password authentication disabled."
    warn "SSH service restart deferred until reboot to avoid disconnecting your SSH session."
    log "SSH hardening complete."
}

check_nfs_share() {
    sleep $LONG_DELAY
    if [ ! -d /mnt/linux/scripts ] || [ ! -r /mnt/linux/scripts ]; then
        error "/mnt/linux/scripts is not accessible. Please ensure the NFS share is mounted and available."
    fi
}

setup_rsyslog() {
    log "Setup rsyslog"
    sleep $SHORT_DELAY
    
    if [ -d "$(dirname "$0")/configs/etc/rsyslog.d" ]; then
        sudo cp "$(dirname "$0")/configs/etc/rsyslog.d/"* /etc/rsyslog.d/
        sudo chmod 644 /etc/rsyslog.d/*
        sudo systemctl restart rsyslog
        log "Rsyslog configuration updated successfully."
    else
        warn "Rsyslog config directory not found in configs/etc/rsyslog.d/. Skipping rsyslog setup."
    fi
}

setup_cron() {
    log "Populating CRON"
    sleep $LONG_DELAY
    
    # Check if sync-distributed.sh exists before executing
    if [ -f "/mnt/linux/scripts/sync-distributed.sh" ]; then
        sudo bash -c "/mnt/linux/scripts/sync-distributed.sh"
        log "sync-distributed.sh completed with exit code $?"
    else
        warn "sync-distributed.sh not found at /mnt/linux/scripts/. Skipping sync setup."
    fi
    
    if [ -d "$(dirname "$0")/configs/cron" ]; then
        sudo cp -v "$(dirname "$0")/configs/cron/"* /etc/cron.d/
        sudo chmod 644 /etc/cron.d/*
        # Remove any previous backup-system.sh lines before adding a new one (idempotency)
        sudo sed -i '/backup-system.sh/d' /etc/cron.d/backup-system
        # Randomize the backup time and update the cron job
        hour=$((1 + $RANDOM % 6))
        minute=$((1 + $RANDOM % 59))
        sudo sh -c "echo '$minute $hour * * 7   root   $(dirname "$0")/scripts/backup-system.sh' >> /etc/cron.d/backup-system"
        log "Cron jobs configured successfully."
    else
        warn "Cron config directory not found in configs/cron/. Skipping cron setup."
    fi
}

setup_certs() {
    log "Certificate Setup"
    sleep $LONG_DELAY
    
    if [ -f "/mnt/linux/scripts/manage-certs.sh" ]; then
        source "/mnt/linux/scripts/manage-certs.sh"
        log "Certificate management script executed successfully."
    else
        warn "manage-certs.sh not found at /mnt/linux/scripts/. Skipping certificate setup."
    fi
}

setup_postfix() {
    log "Setting up Postfix..."
    sleep $SHORT_DELAY
    
    if [ -f "$(dirname "$0")/scripts/setup-postfix.sh" ]; then
        source "$(dirname "$0")/scripts/setup-postfix.sh"
        log "Postfix setup script executed successfully."
    else
        warn "Postfix setup script not found. Skipping..."
    fi
}

setup_zsh() {
    log "Setup ZSH"
sleep $SHORT_DELAY
    source "$(dirname "$0")/scripts/setup-zsh.sh"
}

reboot_prompt() {
read -r -p "Setup complete. Reboot now? [Y/n] " input
input=${input:-Y}
case $input in
    [yY][eE][sS]|[yY])
            log "Rebooting system..."
        sudo reboot
        ;;
    [nN][oO]|[nN])
            log "Reboot skipped. Please reboot manually to apply changes."
        ;;
    *)
            warn "Invalid input. Reboot skipped."
        ;;
esac
}

wait_for_1password_account_add() {
    if command -v op &> /dev/null; then
        echo ""
        echo "────────────────────────────────────────────────────────────"
        echo "🔑  1Password Setup: Use your Keyboard Maestro hotkeys!"
        echo ""
        echo "  ⌃⌥⌘S   →   Paste your 1Password Secret Key"
        echo "  ⌃⌥⌘P   →   Paste your 1Password Master Password"
        echo ""
        echo "When prompted below, use the hotkeys above to quickly fill in your credentials."
        echo "────────────────────────────────────────────────────────────"
        echo ""

        log "Adding 1Password account to CLI."
        op_signin_address="my.1password.com"
        op_email="greg@802ski.com"
        read -p "1Password Secret Key (starts with A3-...): " op_secret
        op_account_name="The Family"

        op account add --address "$op_signin_address" --email "$op_email" --secret-key "$op_secret" --shorthand "$op_account_name"

        if op account list | grep -q "$op_email"; then
            log "1Password account added successfully."
        else
            error "1Password account add failed. Please check your credentials and try again."
        fi
    fi
}

wait_for_1password_signin() {
    if command -v op &> /dev/null; then
        log "Signing in to 1Password CLI to enable secret access."
        eval "$(op signin)"
        # Check if sign-in was successful
        if op account get &> /dev/null; then
            log "1Password CLI sign-in successful. Continuing setup."
        else
            error "1Password CLI sign-in failed. Please check your credentials and try again."
        fi
    fi
}

main() {
    setup_hosts_file
    install_1password
    wait_for_1password_account_add
    wait_for_1password_signin
    update_bashrc
    set_timezone
    install_packages
    setup_virtualization_tools
    install_glances
    setup_autofs
    setup_samba
    setup_github_ssh_key_from_server
    setup_ssh_github
    setup_ssh_hardening
    check_nfs_share
    setup_rsyslog
    setup_cron
    setup_certs
    setup_postfix
    setup_zsh
    reboot_prompt
}

main "$@"

