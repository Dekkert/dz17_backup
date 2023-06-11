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

