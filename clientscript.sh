#!/bin/bash
sudo su
timedatectl set-timezone Europe/Moscow
#yum update
yum -y install epel-release
yum repolist
yum -y install vim
yum install ntp -y && systemctl start ntpd && systemctl enable ntpd
echo "192.168.56.150    client" >> /etc/hosts
echo "192.168.56.160    server" >> /etc/hosts
ssh-keygen -f ~/.ssh/id_rsa -t rsa -N ''
cp /tmp/files/borg-backup.sh /etc/
cp /tmp/files/borg-backup.timer /etc/systemd/system
cp /tmp/files/borg-backup.service /etc/systemd/system
chmod +x /etc/borg-backup.sh
yum install borgbackup -y
useradd -m borg
