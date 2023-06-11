## Lesson26 - Резервное копирование


Задание: 
Настроить стенд Vagrant с двумя виртуальными машинами: backup_server и client. 
Настроить удаленный бекап каталога /etc c сервера client при помощи borgbackup. Резервные копии должны соответствовать следующим критериям: 

* директория для резервных копий /var/backup. Это должна быть отдельная точка монтирования. В данном случае для демонстрации размер не принципиален, достаточно будет и 2GB;
* репозиторий дле резервных копий должен быть зашифрован ключом или паролем - на ваше усмотрение;
* имя бекапа должно содержать информацию о времени снятия бекапа;
* глубина бекапа должна быть год, хранить можно по последней копии на конец месяца, кроме последних трех. Последние три месяца должны содержать копии на каждый день. Т.е. должна быть правильно настроена политика удаления старых бэкапов;
* резервная копия снимается каждые 5 минут. Такой частый запуск в целях демонстрации;
* написан скрипт для снятия резервных копий. Скрипт запускается из соответствующей Cron джобы, либо systemd timer-а - на ваше усмотрение;
* настроено логирование процесса бекапа. Для упрощения можно весь вывод перенаправлять в logger с соответствующим тегом. Если настроите не в syslog, то обязательна ротация логов.
* Запустите стенд на 30 минут.
* Убедитесь что резервные копии снимаются.
* Остановите бекап, удалите (или переместите) директорию /etc и восстановите ее из бекапа.


### Выполнение

Листинг Vagrantfile 
bserver - машина с доп. диском примонтированным в /var/backup на которую отправляются бекапы.
bclient - машина которая отправляет бекапы.


```
rul@rul-virtual-machine:~/dz17_backup$ cat Vagrantfile 
# -*- mode: ruby -*-
# vim: set ft=ruby :
disk_controller = 'IDE' # MacOS. This setting is OS dependent. Details https://github.com/hashicorp/vagrant/issues/8105
 
MACHINES = {
  :bserver => {
        :box_name => "centos/7",
        :box_version => "2004.01",
    :disks => {
        :sata1 => {
            :dfile => './sata1.vdi',
            :size => 2048,
            :port => 1
        },
    }
        
  },
}
 
Vagrant.configure("2") do |config|
 
  MACHINES.each do |boxname, boxconfig|
      config.vm.define "bclient" do |bclient|
       bclient.vm.box = "centos/7" 
       bclient.vm.provision "file", source: "./files/", destination: "/tmp/"
       bclient.vm.provision "shell", path: "clientscript.sh" 
       bclient.vm.network "private_network", ip: "192.168.56.150"
       bclient.vm.host_name = "client"
      end

      config.vm.define boxname do |box|
 
        box.vm.box = boxconfig[:box_name]
        box.vm.box_version = boxconfig[:box_version]
        box.vm.network "private_network", ip: "192.168.56.160"     
        box.vm.host_name = "server"
        box.vm.provision "shell", path: "serverscript.sh" 

 
        box.vm.provider :virtualbox do |vb|
              vb.customize ["modifyvm", :id, "--memory", "1024"]
              needsController = false
        boxconfig[:disks].each do |dname, dconf|
              unless File.exist?(dconf[:dfile])
              vb.customize ['createhd', '--filename', dconf[:dfile], '--variant', 'Fixed', '--size', dconf[:size]]
         needsController =  true
         end
        end
            if needsController == true
                vb.customize ["storagectl", :id, "--name", "SATA", "--add", "sata" ]
                boxconfig[:disks].each do |dname, dconf|
                vb.customize ['storageattach', :id,  '--storagectl', 'SATA', '--port', dconf[:port], '--device', 0, '--type', 'hdd', '--medium', dconf[:dfile]]
                end
             end
          end
    end
  end
end

```

Проверяем, что диск подмонтировался:

```
root@server ~]# df -Ht
df: option requires an argument -- 't'
Try 'df --help' for more information.
[root@server ~]# df -Th
Filesystem     Type      Size  Used Avail Use% Mounted on
devtmpfs       devtmpfs  489M     0  489M   0% /dev
tmpfs          tmpfs     496M     0  496M   0% /dev/shm
tmpfs          tmpfs     496M  6.7M  489M   2% /run
tmpfs          tmpfs     496M     0  496M   0% /sys/fs/cgroup
/dev/sdb1      xfs        40G  5.4G   35G  14% /
/dev/sda       ext4      2.0G  6.0M  1.8G   1% /var/backup
tmpfs          tmpfs     100M     0  100M   0% /run/user/1000
```

Скрипт(*clientscript.sh*) который выполняется на клиенте для:
* установки borgbackup
* Создания ключевой пары
* Добавления обоих ВМ в /etc/hosts
* копирования в соответствующие директории таймера, юнита службы, скрипта выполняющего бекап.
* присвоения разрешений на исполнение
* добавление пользователя

```
rul@rul-virtual-machine:~/dz17_backup$ cat clientscript.sh 
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

```

Скрипт(*serverscript.sh*) который выполняется на сервере для:
* установки borgbackup
* создания директории /var/backup/
* назначение прав на /var/backup/
* монтирования диска в /var/backup/
* Добавления обоих ВМ в /etc/hosts
* добавление пользователя

```
rul@rul-virtual-machine:~/dz17_backup$ cat serverscript.sh 
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

```

Листинг таймера(*borg-backup.timer*):
```
rul@rul-virtual-machine:~/dz17_backup/files$ cat borg-backup.timer 
[Unit]
Description=Automated Borg Backup Timer

[Timer]
OnCalendar=*:0/5

[Install]
WantedBy=timers.target

```

Листинг юнита(*borg-backup.service*):
```
rul@rul-virtual-machine:~/dz17_backup/files$ cat borg-backup.service 
[Unit]
Description=Automated Borg Backup
After=network.target

[Service]
Type=oneshot
ExecStart=/etc/borg-backup.sh

[Install]
WantedBy=multi-user.target

```

Листинг скрипта, который выполняет бекапы согласно заданным условиям:

```
rul@rul-virtual-machine:~/dz17_backup/files$ cat borg-backup.sh
#!/usr/bin/env bash
# the envvar $REPONAME is something you should just hardcode

export REPOSITORY="borg@192.168.56.160:/var/backup"


# Fill in your password here, borg picks it up automatically
export BORG_PASSPHRASE="repokey"

# Backup all of /home except a few excluded directories and files
borg create -v --stats --compression lz4                 \
    $REPOSITORY::'{hostname}-{now:%Y-%m-%d_%H:%M:%S}' /etc \

# Route the normal process logging to journalctl
2>&1

# If there is an error backing up, reset password envvar and exit
if [ "$?" = "1" ] ; then
    export BORG_PASSPHRASE=""
    exit 1
fi

# Prune the repo of extra backups
borg prune -v $REPOSITORY --prefix '{hostname}-'         \
    --keep-minutely=120                                  \
    --keep-daily=90                                       \
    --keep-monthly=12                                     \
    --keep-yearly=1                                     \

borg list $REPOSITORY

# Unset the password
export BORG_PASSPHRASE=""
exit

```

### Выполняем настройку

**заходим на клиента и инициализируем репозиторий**

```
[root@client ~]# borg init -e=repokey borg@192.168.56.160:/var/backup
Enter new passphrase: 
Enter same passphrase again: 
Do you want your passphrase to be displayed for verification? [yN]: n

```

перезагружаем:
```
systemctl daemon-reload
```

Добавляем в автозагрузку:
```
[root@client etc]# systemctl enable borg-backup.timer
Created symlink from /etc/systemd/system/timers.target.wants/borg-backup.timer to /etc/systemd/system/borg-backup.timer.
```

Стартуем и проверяем:
```
[root@client etc]# systemctl start borg-backup.timer
[root@client etc]# systemctl status borg-backup.timer
● borg-backup.timer - Automated Borg Backup Timer
   Loaded: loaded (/etc/systemd/system/borg-backup.timer; enabled; vendor preset: disabled)
   Active: active (waiting) since Sun 2023-06-11 09:32:58 MSK; 2min 35s ago
```

Проверяем работу таймера:

```
[root@client etc]# systemctl list-timers --all
NEXT                         LEFT          LAST                         PASSED      UNIT                         ACTIVATES
Sun 2023-06-11 09:40:00 MSK  3min 46s left Sun 2023-06-11 09:35:08 MSK  1min 4s ago borg-backup.timer            borg-backup.service
```

Проверяем логи:
```
[root@client etc]# journalctl -u borg-backup
-- Logs begin at Sun 2023-06-11 08:28:36 MSK, end at Sun 2023-06-11 09:41:01 MSK. --
Jun 11 09:31:54 client systemd[1]: Starting Automated Borg Backup...
Jun 11 09:31:55 client borg-backup.sh[25152]: Creating archive at "borg@192.168.11.160:/var/backup::client-2023-06-11_09:31:54"
Jun 11 09:31:55 client borg-backup.sh[25152]: ------------------------------------------------------------------------------
Jun 11 09:31:55 client borg-backup.sh[25152]: Archive name: client-2023-06-11_09:31:54
Jun 11 09:31:55 client borg-backup.sh[25152]: Archive fingerprint: 302a3821e0df70a0be5fd12de444465b65a2eadc2faf9066435007435296cd75
Jun 11 09:31:55 client borg-backup.sh[25152]: Time (start): Sun, 2023-06-11 09:31:54
Jun 11 09:31:55 client borg-backup.sh[25152]: Time (end):   Sun, 2023-06-11 09:31:55
Jun 11 09:31:55 client borg-backup.sh[25152]: Duration: 0.29 seconds
Jun 11 09:31:55 client borg-backup.sh[25152]: Number of files: 1714
Jun 11 09:31:55 client borg-backup.sh[25152]: Utilization of max. archive size: 0%
Jun 11 09:31:55 client borg-backup.sh[25152]: ------------------------------------------------------------------------------
Jun 11 09:31:55 client borg-backup.sh[25152]: Original size      Compressed size    Deduplicated size
Jun 11 09:31:55 client borg-backup.sh[25152]: This archive:               28.44 MB             13.51 MB             50.83 kB
Jun 11 09:31:55 client borg-backup.sh[25152]: All archives:              142.22 MB             67.53 MB             12.05 MB
Jun 11 09:31:55 client borg-backup.sh[25152]: Unique chunks         Total chunks
Jun 11 09:31:55 client borg-backup.sh[25152]: Chunk index:                    1304                 8550
Jun 11 09:31:55 client borg-backup.sh[25152]: ------------------------------------------------------------------------------
Jun 11 09:31:57 client borg-backup.sh[25152]: client-2023-06-11_09:21:42           Sun, 2023-06-11 09:21:43 [af7eb64831ff19bf4b7ab3909dc8b5ed62ccde3dba6c4320fbb0cf0f782d741c]
Jun 11 09:31:57 client borg-backup.sh[25152]: client-2023-06-11_09:27:41           Sun, 2023-06-11 09:27:42 [454b57eabf0f7d614dec021dc7d8a6a15ba7f34e30bc0eea1d1e56199de712d4]
Jun 11 09:31:57 client borg-backup.sh[25152]: client-2023-06-11_09:28:01           Sun, 2023-06-11 09:28:01 [48e89a356579ab2e7ff1f07db719088d0542a62dac16f33bfad495f9b16269de]
Jun 11 09:31:57 client borg-backup.sh[25152]: client-2023-06-11_09:31:54           Sun, 2023-06-11 09:31:54 [302a3821e0df70a0be5fd12de444465b65a2eadc2faf9066435007435296cd75]
Jun 11 09:31:57 client systemd[1]: Started Automated Borg Backup.
Jun 11 09:35:08 client systemd[1]: Starting Automated Borg Backup...
Jun 11 09:35:09 client borg-backup.sh[25264]: Creating archive at "borg@192.168.11.160:/var/backup::client-2023-06-11_09:35:09"
Jun 11 09:35:10 client borg-backup.sh[25264]: ------------------------------------------------------------------------------
Jun 11 09:35:10 client borg-backup.sh[25264]: Archive name: client-2023-06-11_09:35:09
Jun 11 09:35:10 client borg-backup.sh[25264]: Archive fingerprint: d000c8303eeec1b88f7183cd52a862276281415d4c1a01b064a534d57b52741d
Jun 11 09:35:10 client borg-backup.sh[25264]: Time (start): Sun, 2023-06-11 09:35:09
Jun 11 09:35:10 client borg-backup.sh[25264]: Time (end):   Sun, 2023-06-11 09:35:10
Jun 11 09:35:10 client borg-backup.sh[25264]: Duration: 0.29 seconds
Jun 11 09:35:10 client borg-backup.sh[25264]: Number of files: 1714
```

Проверяем, что бекапы создаются каждые 5 мин:

```
[root@client etc]# borg list borg@192.168.11.160:/var/backup
Enter passphrase for key ssh://borg@192.168.11.160/var/backup: 
MyFirstBackup-2023-06-11_09:15:28    Sun, 2023-06-11 09:15:28 [7bcd2eb469a502896c2bf4d25de0c002ef84ea6ac57cf635a56255f74c5963ee]
client-2023-06-11_09:21:42           Sun, 2023-06-11 09:21:43 [af7eb64831ff19bf4b7ab3909dc8b5ed62ccde3dba6c4320fbb0cf0f782d741c]
client-2023-06-11_09:27:41           Sun, 2023-06-11 09:27:42 [454b57eabf0f7d614dec021dc7d8a6a15ba7f34e30bc0eea1d1e56199de712d4]
client-2023-06-11_09:28:01           Sun, 2023-06-11 09:28:01 [48e89a356579ab2e7ff1f07db719088d0542a62dac16f33bfad495f9b16269de]
client-2023-06-11_09:31:54           Sun, 2023-06-11 09:31:54 [302a3821e0df70a0be5fd12de444465b65a2eadc2faf9066435007435296cd75]
client-2023-06-11_09:35:09           Sun, 2023-06-11 09:35:09 [d000c8303eeec1b88f7183cd52a862276281415d4c1a01b064a534d57b52741d]
client-2023-06-11_09:40:09           Sun, 2023-06-11 09:40:09 [882e4cb6172cc1d039e1ef82b1a4cabeea8cda69528284cd6c81e83556f07e88]
client-2023-06-11_09:45:08           Sun, 2023-06-11 09:45:09 [3afbc9d2249ae953134a68c9dd78f6c5310715a1b33f9c75194b0ba885add1b4]
client-2023-06-11_09:50:09           Sun, 2023-06-11 09:50:09 [255a763f15a180f7b49f371f3268ced3060252ff0a9ca7a933458fb82beacddb]
client-2023-06-11_09:55:09           Sun, 2023-06-11 09:55:09 [4f9bb26b0a19a452535b065f611670a28ca157e2a101637a81145377c8b72a64]
client-2023-06-11_10:00:09           Sun, 2023-06-11 10:00:09 [d67ef85b13a6dc52e918f8e7e2dfaa15f67172e998945bb410f8815751390e0a]
client-2023-06-11_10:05:09           Sun, 2023-06-11 10:05:09 [4c8c615932cbb0c8158e6d2952cc8e8e50dcc495c5e393039081e9b2185c9387]
client-2023-06-11_10:10:09           Sun, 2023-06-11 10:10:09 [dfd4cc939b41316ac783a52b2b1eeb3c516250ee1be134bfc34f34be028ae1a5]
client-2023-06-11_10:15:09           Sun, 2023-06-11 10:15:09 [d22a6a5a31896118db33c2eae1785947c0821b893be9e3ad560b1fffc88f672a]
client-2023-06-11_10:20:09           Sun, 2023-06-11 10:20:09 [0a2c37d0d0e7820be579457760eaa616ac84e5f9b79a385909e6955eccf1a3dd]
client-2023-06-11_10:25:09           Sun, 2023-06-11 10:25:09 [416f14003c13da4445510f6ae0ea4abce6895b51035dce525cca8621896a866b]
client-2023-06-11_10:30:09           Sun, 2023-06-11 10:30:09 [f6448466fd5f9f363109ea0c46070b8829cab4b1f3d72ac268d586247a902bf6]
client-2023-06-11_10:35:09           Sun, 2023-06-11 10:35:09 [b55f43803ef8011776b00980684814df4190662332691a0739d17aec257d3278]
client-2023-06-11_10:40:09           Sun, 2023-06-11 10:40:09 [6a90f7b903c1d13733b6660e374ea4f5c50856e89ebe8b7931de6f46a8cc2b59]
client-2023-06-11_10:45:09           Sun, 2023-06-11 10:45:09 [32d58439a05a924806e169112721aba84993e8205142ac8b841edc82a7ef66a8]
client-2023-06-11_10:50:09           Sun, 2023-06-11 10:50:09 [ad5c6917956c17d90b4890d08e9ef156321da7d6a3e2dd7ace8a767bc68a7be5]
client-2023-06-11_10:55:09           Sun, 2023-06-11 10:55:09 [e86aa73696e0a1b7afdb8221f629223ba9689d125267d9a161ed2d27c6f39874]
```

Проверяем восстановление:

```
[root@client ~]# mkdir ~/restore && cd ~/restore
[root@client restore]# borg extract borg@192.168.11.160:/var/backup::client-2023-06-11_10:45:09
Enter passphrase for key ssh://borg@192.168.11.160/var/backup: 
[root@client restore]# pwd
/root/restore
[root@client restore]# dir /etc/
adjtime			 chkconfig.d   csh.login		exports      grub.d	  inputrc	 localtime	 my.cnf.d	    pam.d	    profile.d  redhat-release	 securetty	subgid		system-release-cpe  xinetd.d
aliases			 chrony.conf   dbus-1			exports.d    gshadow	  iproute2	 login.defs	 netconfig	    passwd	    protocols  request-key.conf  security	subgid-		tcsd.conf	    yum
aliases.db		 chrony.keys   default			filesystems  gshadow-	  issue		 logrotate.conf  NetworkManager     passwd-	    python     request-key.d	 selinux	subuid		terminfo	    yum.conf
alternatives		 cifs-utils    depmod.d			firewalld    gss	  issue.net	 logrotate.d	 networks	    pkcs11	    qemu-ga    resolv.conf	 services	subuid-		tmpfiles.d	    yum.repos.d
anacrontab		 cron.d        dhcp			fstab	     gssproxy	  krb5.conf	 machine-id	 nfs.conf	    pki		    rc0.d      rpc		 sestatus.conf	sudo.conf	tuned
audisp			 cron.daily    DIR_COLORS		fuse.conf    host.conf	  krb5.conf.d	 magic		 nfsmount.conf	    pm		    rc1.d      rpm		 shadow		sudoers		udev
audit			 cron.deny     DIR_COLORS.256color	gcrypt	     hostname	  ld.so.cache	 man_db.conf	 nsswitch.conf	    polkit-1	    rc2.d      rsyncd.conf	 shadow-	sudoers.d	vconsole.conf
bash_completion.d	 cron.hourly   DIR_COLORS.lightbgcolor	gnupg	     hosts	  ld.so.conf	 mke2fs.conf	 nsswitch.conf.bak  popt.d	    rc3.d      rsyslog.conf	 shells		sudo-ldap.conf	vimrc
bashrc			 cron.monthly  dracut.conf		GREP_COLORS  hosts.allow  ld.so.conf.d	 modprobe.d	 ntp		    postfix	    rc4.d      rsyslog.d	 skel		sysconfig	virc
binfmt.d		 crontab       dracut.conf.d		groff	     hosts.deny   libaudit.conf  modules-load.d  ntp.conf	    ppp		    rc5.d      rwtab		 ssh		sysctl.conf	vmware-tools
borg-backup.sh		 cron.weekly   e2fsck.conf		group	     idmapd.conf  libnl		 motd		 openldap	    prelink.conf.d  rc6.d      rwtab.d		 ssl		sysctl.d	wpa_supplicant
centos-release		 crypttab      environment		group-	     init.d	  libuser.conf	 mtab		 opt		    printcap	    rc.d       samba		 statetab	systemd		X11
centos-release-upstream  csh.cshrc     ethertypes		grub2.cfg    inittab	  locale.conf	 my.cnf		 os-release	    profile	    rc.local   sasl2		 statetab.d	system-release	xdg
```
