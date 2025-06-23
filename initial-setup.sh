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

set_hostname() {
    log "Setting Hostname..."
    current_hostname=$(hostname)
domain_name=$(grep DOMAINNAME /run/systemd/netif/leases/* 2>/dev/null | awk -F= '{print $2}')
if [[ -n "$domain_name" ]]; then
        # Only append domain if not already present
        if [[ "$current_hostname" == *.$domain_name ]]; then
            fqdn="$current_hostname"
        else
    fqdn="${current_hostname}.${domain_name}"
        fi
else
        warn "No domain name detected from DHCP."
    fqdn="${current_hostname}"
    read -p "Enter fqdn :" fqdn
fi
    log "Current Hostname : $current_hostname"
    log "FQDN : $fqdn"
    if [[ $current_hostname != "$fqdn" ]]; then
    read -r -p "Change Hostname to '$fqdn'? [Y/n] " input
    case $input in
            [yY][eE][sS]|[yY]|"") ;;
            [nN][oO]|[nN]) log "Hostname change skipped."; return ;;
            *) warn "Invalid input. Skipping hostname change."; return ;;
        esac
        log "Updating hostname to $fqdn..."
            sudo hostnamectl set-hostname "$fqdn"
            short_hostname=$(echo "$fqdn" | cut -d. -f1)
        log "Updating /etc/hosts..."
            sudo sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $fqdn $short_hostname/" /etc/hosts
        log "Hostname successfully updated to $fqdn"
    else
        log "Hostname already set to $fqdn. Skipping."
    fi
}

update_bashrc() {
    log "Updating BASH"
sleep $SHORT_DELAY
    if ! grep -q "$(dirname "$0")/scripts" ~/.bashrc; then
        echo "export PATH=\$PATH:$(dirname "$0")/scripts" >> ~/.bashrc
fi
source ~/.bashrc
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
    nfs-common ntp cifs-utils \
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

    # Create Samba user if needed
    read -r -p "Create Samba user? [y/N] " input
    case $input in
        [yY][eE][sS]|[yY])
            read -p "Enter Samba username: " samba_user
            sudo smbpasswd -a "$samba_user"
            ;;
        *)
            log "Samba user creation skipped."
            ;;
    esac

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
    FILE="$(dirname "$0")/scripts/setup_postfix_v2.sh"
if [ ! -f "$FILE" ]; then
       error "Required script file not found: $FILE"
    fi
}

setup_rsyslog() {
    log "Setup rsyslog"
sleep $SHORT_DELAY
    sudo cp "$(dirname "$0")/configs/rsyslog.d/"* /etc/rsyslog.d
sudo chmod 644 /etc/rsyslog.d/*
sudo systemctl restart rsyslog
}

setup_cron() {
    log "Populating CRON"
sleep $LONG_DELAY
    sudo bash -c "source /mnt/linux/scripts/sync-distributed.sh"
    sudo cp -v "$(dirname "$0")/configs/cron/"* /etc/cron.d
sudo chmod 644 /etc/cron.d/*
    # Remove any previous backup-system.sh lines before adding a new one (idempotency)
    sudo sed -i '/backup-system.sh/d' /etc/cron.d/backup-system
    # Randomize the backup time and update the cron job
hour=$((1 + $RANDOM % 6))
minute=$((1 + $RANDOM % 59))
    sudo sh -c "echo '$minute $hour * * 7   root   $(dirname "$0")/scripts/backup-system.sh' >> /etc/cron.d/backup-system"
}

download_certs() {
    log "Certificate Setup"
sleep $LONG_DELAY
    source "/mnt/linux/scripts/manage-certs.sh"
}

setup_postfix() {
    log "Setting up Postfix..."
sleep $SHORT_DELAY
    if [ -f "$(dirname "$0")/scripts/setup_postfix_v2.sh" ]; then
        source "$(dirname "$0")/scripts/setup_postfix_v2.sh"
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
    install_1password
    wait_for_1password_account_add
    wait_for_1password_signin
    set_hostname
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
    download_certs
    setup_postfix
    setup_zsh
    
    reboot_prompt
}

main "$@"

