#!/bin/bash
# Initial Ubuntu System Setup Script
# Last Revised: 2025/01/03
# Purpose: Automates initial configuration on new Ubuntu installs

# Set the FQDN hostname
echo "Setting Hostname..."
current_hostname=$(hostname)
domain_name=$(grep DOMAINNAME /run/systemd/netif/leases/* 2>/dev/null | awk -F= '{print $2}')

if [[ -n "$domain_name" ]]; then
    fqdn="${current_hostname}.${domain_name}"
else
    echo "Warning: No domain name detected from DHCP."
    fqdn="${current_hostname}"
fi

echo "Current Hostname : $current_hostname"
echo "FQDN : $fqdn"

while true; do
    read -r -p "Change Hostname to '$fqdn'? [Y/n] " input
    case $input in
        [yY][eE][sS]|[yY])
            echo "Updating hostname to $fqdn..."
            # Update the system's hostname
            sudo hostnamectl set-hostname "$fqdn"

            # Extract short hostname for /etc/hosts
            short_hostname=$(echo "$fqdn" | cut -d. -f1)

            # Update /etc/hosts
            echo "Updating /etc/hosts..."
            sudo sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $fqdn $short_hostname/" /etc/hosts

            echo "Hostname successfully updated to $fqdn"
            break
            ;;
        [nN][oO]|[nN])
            echo "Hostname change skipped."
            break
            ;;
        *)
            echo "Invalid input. Please enter 'Y' or 'N'."
            ;;
    esac
done
# Update the bashrc to add the NFS Mount directory to the path
echo "Updating BASH"
if ! grep -q "/mnt/linux/scripts" ~/.bashrc; then
    echo "export PATH=\$PATH:/mnt/linux/scripts" >> ~/.bashrc
fi
source ~/.bashrc

# set TimeZone
echo "Setting timezone to America/New_York..."
sudo timedatectl set-timezone America/New_York
echo "Current timezone: $(timedatectl | grep 'Time zone')"
#
# install base packages

echo "Installing base packages..."
sudo apt update && sudo NEEDRESTART_MODE=a apt dist-upgrade -y
sudo NEEDRESTART_MODE=a apt -y install \
    nfs-common ntp cifs-utils \
    smbclient apt-transport-https ca-certificates curl software-properties-common \
    micro net-tools smartmontools || {
    echo "Error installing base packages. Exiting."; exit 1;
}
echo "iperf3 iperf3/start_autostart boolean true" | sudo debconf-set-selections
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iperf3

# Detmermine the virtualization technology being used
# qemu = KVM, hyperv = Microsoft

virt=$(systemd-detect-virt)
if [ "$virt" = "microsoft" ]; then
    echo "Detected Microsoft Hyper-V. Installing virtualization tools..."
    sudo NEEDRESTART_MODE=a apt -y install linux-virtual linux-cloud-tools-virtual linux-tools-virtual
else
    echo "No specific virtualization tools required for $virt."
fi

#
echo "Installing Glances for system monitoring..."
sudo snap install glances || {
    echo "Failed to install Glances."; exit 1;
}
#
sudo systemctl daemon-reload
setup_autofs() {
    echo "Setting up AUTOFS for NFS mounts..."
    sudo NEEDRESTART_MODE=a apt -y install autofs
    sudo sh -c "echo '' >> /etc/auto.master"
    sudo sh -c "echo '/mnt    /etc/auto.nfs --timeout=180' >> /etc/auto.master"
    sudo sh -c "echo '' >> /etc/auto.nfs"
    sudo sh -c "echo '# NFS Mounts' >> /etc/auto.nfs"
    sudo sh -c "echo 'backup -fstype=nfs4,rw,soft    hal.hq.802ski.com:/mnt/user/backup' >> /etc/auto.nfs"
    sudo sh -c "echo 'linux -fstype=nfs4,rw,soft     hal.hq.802ski.com:/mnt/user/linux' >> /etc/auto.nfs"
    sudo systemctl restart autofs
}
setup_autofs

#
# Setup SSH for Github
#
echo "Setting up SSH for GitHub..."
if [ -d /mnt/linux/setup/ssh ]; then
    cp -r /mnt/linux/setup/ssh/* ~/.ssh
    chmod 700 ~/.ssh
    chmod 600 ~/.ssh/*
else
    echo "SSH setup directory not found. Skipping..."
fi

#
# check to make sure that the linux share exists
#
sleep 5s
FILE=/mnt/linux/scripts/setup_postfix_v2.sh
if [ ! -f "$FILE" ]; then
   echo "NFS File share not available!"
   exit 1 # if it doesn't then stop
fi

#setup rsyslog
#
echo "Setup rsyslog"
sudo cp /mnt/linux/setup/rsyslog.d/* /etc/rsyslog.d
sudo chmod 644 /etc/rsyslog.d/*
sudo systemctl restart rsyslog
#
# Setup CRON
#
echo "Populating CRON"
sudo cp -v /mnt/linux/setup/cron/* /etc/cron.d
sudo chmod 644 /etc/cron.d/*
# let's randomize the backup time and update the cron job
hour=$((1 + $RANDOM % 6))
minute=$((1 + $RANDOM % 59))
sudo sh -c "echo '$minute $hour * * 7   root   /mnt/linux/scripts/system-backup.sh' >> /etc/cron.d/system-backup"
#
# Download wilidcard certs
#
echo "Certiciate Setup"
source /mnt/linux/lego/download-cert.sh
#
# Update logrotate
#sudo chmod 644 /etc/logrotate.d/autoremove

if [ "$virt" = "microsoft" ]
then
    echo "Setup Virtual Guest Services"
    # Setup hyper-v Guest Services
    sudo sh -c "echo 'hv_vmbus' >> /etc/initramfs-tools/modules"
    sudo sh -c "echo 'hv_storvsc' >> /etc/initramfs-tools/modules"
    sudo sh -c "echo 'hv_blkvsc' >> /etc/initramfs-tools/modules"
    sudo sh -c "echo 'hv_netvsc' >> /etc/initramfs-tools/modules"
    sudo update-initramfs -u
fi
# install and configure the mail server
echo "Setting up Postfix..."
if [ -f /mnt/linux/scripts/setup-postfix.sh ]; then
    source /mnt/linux/scripts/setup-postfix.sh
else
    echo "Postfix setup script not found. Skipping..."
fi

echo "Setup ZSH"
source /mnt/linux/scripts/setup-zsh.sh

echo "Done!"
read -r -p "Setup complete. Reboot now? [Y/n] " input
case $input in
    [yY][eE][sS]|[yY])
        echo "Rebooting system..."
        sudo reboot
        ;;
    [nN][oO]|[nN])
        echo "Reboot skipped. Please reboot manually to apply changes."
        ;;
    *)
        echo "Invalid input. Reboot skipped."
        ;;
esac

