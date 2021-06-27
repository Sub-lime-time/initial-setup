#! /bin/bash

# Revised: 2021/06/27
# First, detmermine the virtualization technology being used
# qemu = KVM, hyperv = Microsoft
virt=$(systemd-detect-virt)

# Update the bashrc to add the NFS Mount directory to the path
echo "Setting up BASH"
echo "export PATH=$PATH:/mnt/linux/scripts" >> ~/.bashrc
source ~/.bashrc

# Now switch to Root
#sudo -i
# install base packages
sudo apt update
sudo apt dist-upgrade -y
sudo apt -y install nfs-common autofs ntp landscape-client iperf3 cifs-utils \
   smbclient apt-transport-https ca-certificates curl software-properties-common

if [ "$virt" = "microsoft" ]
then
   #only install cloud packages if it's hyper-v
   sudo apt -y install linux-virtual linux-cloud-tools-virtual linux-tools-virtual
fi
sudo snap install glances
echo "Setting up AUTOFS"
# update NFS Mounts and mount them
sudo sh -c "echo '' >> /etc/auto.master"
sudo sh -c "echo '/mnt    /etc/auto.nfs --timeout=180' >> /etc/auto.master"
sudo sh -c "echo '' >> /etc/auto.nfs"
sudo sh -c "echo '# NFS Mounts' >> /etc/auto.nfs"
sudo sh -c "echo 'backup -fstype=nfs,rw,soft,intr hal.lh.802ski.com:/mnt/user/backup' >> /etc/auto.nfs"
sudo sh -c "echo 'linux -fstype=nfs,rw,soft,intr hal.lh.802ski.com:/mnt/user/linux' >> /etc/auto.nfs"

sudo systemctl restart autofs
#
# check to make sure that the linux share exists
#
sleep 5s
FILE=/mnt/linux/scripts/setup-postfix
if [ ! -f "$FILE" ]; then
   echo "NFS File share not available!"
   exit 1 # if it doesn't then stop
fi
# set TimeZone
sudo timedatectl set-timezone America/New_York
echo "Prep Landscape"
# prep Landscape Client
sudo mkdir -p /etc/landscape
sudo cp /mnt/linux/landscape/landscape_server_ca.crt /etc/landscape
sudo chgrp landscape /etc/landscape/landscape_server_ca.crt
sudo sh -c "echo 'ssl_public_key = /etc/landscape/landscape_server_ca.crt' >> /etc/landscape/client.conf"
#setup System Backup
#sudo sh -c "echo '#' >> /etc/crontab"
#sudo sh -c "echo '# System Backup' >> /etc/crontab"
#sudo sh -c "echo '#' >> /etc/crontab"
#sudo sh -c "echo '45 1    * * 7   root   /mnt/common/scripts/system-backup.sh' >> /etc/crontab"
#sudo sh -c "echo '#' >> /etc/crontab"
#sudo sh -c "echo '# Autoremove obsolete packages' >> /etc/crontab"
#sudo sh -c "echo '#' >> /etc/crontab"
#sudo sh -c "echo '00 5    * * 5   root  /mnt/common/scripts/autoremove-apps.sh' >> /etc/crontab"
echo "Populating CRON"
sudo cp /mnt/linux/setup/cron/* /etc/cron.d
sudo chmod 644 /etc/cron.d/*
# let's randomize the backup time and update the cron job
hour=$((1 + $RANDOM % 6))
minute=$((1 + $RANDOM % 59))
sudo sh -c "echo '$minute $hour * * 7   root   /mnt/linux/scripts/system-backup.sh' >> /etc/cron.d/system-backup"
#
# Update logrotate
sudo chmod 644 /etc/logrotate.d/autoremove

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
source /mnt/linux/scripts/setup-postfix
echo "Done!"
read -n 1 -s -r -p "Press any key to continue"
sudo reboot

