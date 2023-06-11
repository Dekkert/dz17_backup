#!/bin/bash
sudo su
timedatectl set-timezone Europe/Moscow
#yum update
yum -y install epel-release
yum -y install vim
yum repolist
yum install ntp -y && systemctl start ntpd && systemctl enable ntpd
yum install borgbackup -y
echo "192.168.56.150	client" >> /etc/hosts
echo "192.168.56.160    server" >> /etc/hosts

useradd -m borg
mkdir ~borg/.ssh
touch ~borg/.ssh/authorized_keys
chown -R borg:borg ~borg/.ssh
mkdir /var/backup
yes | mkfs -t ext4 /dev/sda
mount /dev/sda /var/backup/


chown borg:borg /var/backup
