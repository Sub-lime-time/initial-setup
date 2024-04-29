#! /bin/bash

# Revised: 2021/06/27

# Set fqdn hostname
echo "Setting Hostname..."
hn=$(hostname)
fqdn=$(host -TtA $(hostname -s)|grep "has address"|awk '{print $1}') ;
if [[ "${fqdn}" == "" ]] ; then fqn=$(hostname -s) ; fi ; 
echo "Original Hostname : "$hn
echo "FQDN : "$fqdn
echo ""
while true
do
        read -r -p "Change Hostname? [Y/n] " input

        case $input in
            [yY][eE][sS]|[yY])
                        # First update the hosts file
                        sudo sed -i "s/$hn/$fqdn $hn/g" /etc/hosts
                        # then update the hostname via cmd
                        # sudo hostnamectl set-hostname $fqdn
 
                        break
                        ;;
            [nN][oO]|[nN])
                        echo "No"
                        break
                        ;;
            *)
                echo "Invalid input..."
                ;;
        esac
done
# Update the bashrc to add the NFS Mount directory to the path
echo "Updating BASH"
echo "export PATH=$PATH:/mnt/linux/scripts" >> ~/.bashrc
source ~/.bashrc

# Now switch to Root
#sudo -i
# install base packages
sudo apt update
sudo apt dist-upgrade -y
sudo apt -y install nfs-common ntp landscape-client iperf3 cifs-utils \
   smbclient apt-transport-https ca-certificates curl software-properties-common \
   micro net-tools smartmontools

# Detmermine the virtualization technology being used
# qemu = KVM, hyperv = Microsoft

echo "Setup VM tools"
virt=$(systemd-detect-virt)
if [ "$virt" = "microsoft" ]
then
   #only install cloud packages if it's hyper-v
   sudo apt -y install linux-virtual linux-cloud-tools-virtual linux-tools-virtual
fi

#
echo "Install Glances"
sudo snap install glances
#
sudo systemctl daemon-reload
echo "Setup AUTOFS"
# update NFS Mounts and mount them
sudo apt -y install autofs
sudo sh -c "echo '' >> /etc/auto.master"
sudo sh -c "echo '/mnt    /etc/auto.nfs --timeout=180' >> /etc/auto.master"
sudo sh -c "echo '' >> /etc/auto.nfs"
sudo sh -c "echo '# NFS Mounts' >> /etc/auto.nfs"
sudo sh -c "echo 'backup -fstype=nfs4,rw,soft    hal.hq.802ski.com:/mnt/user/backup' >> /etc/auto.nfs"
sudo sh -c "echo 'linux -fstype=nfs4,rw,soft     hal.hq.802ski.com:/mnt/user/linux' >> /etc/auto.nfs"

sudo systemctl restart autofs
#
# Setup SSH for Github
#
cp -r /mnt/linux/ssh/* ~/.ssh

#
# check to make sure that the linux share exists
#
sleep 5s
FILE=/mnt/linux/scripts/setup-postfix.sh
if [ ! -f "$FILE" ]; then
   echo "NFS File share not available!"
   exit 1 # if it doesn't then stop
fi
# set TimeZone
sudo timedatectl set-timezone America/New_York
#
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
sudo cp /mnt/linux/setup/cron/* /etc/cron.d
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
echo "Setup Mail"
source /mnt/linux/scripts/setup-postfix.sh
read -n 1 -s -r -p "Press any key to continue"
echo "Setup ZSH"
source /mnt/linux/scripts/setup-zsh.sh
echo "Done!"
read -n 1 -s -r -p "Press any key to continue"
sudo reboot

