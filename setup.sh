#!/usr/bin/env bash

sudo apt-get update && apt-get upgrade -y

apt-get install -y git \
    build-essential \
    linux-headers-"$(uname -r)" \
    htop \
    iotop \
    vim \
    libpq-dev \
    libssl-dev \
    openssl \
    libffi-dev \
    zlib1g-dev \
    libaio-dev \
    sysstat


# Add the attached disks
disks=$(fdisk -l | grep Disk | grep "/dev" | awk '{print $2}' | cut -d ":" -f1)
for i in ${disks};
do
    if [ "${i}" = "/dev/sda" ]; then
        mkdir -p /os-disk
    elif [ "${i}" = "/dev/sdb" ]; then
        rm -f /ephemeral
        ln -fs /mnt /ephemeral
    else
        umount "${i}" || echo "not mounted"
        sizen=$(fdisk "${i}" -l | grep Disk | grep "/dev" | awk '{print $3$4}' | cut -d "," -f1)
        echo "${i} :: ${sizen}"
        mkdir -p "/${sizen}" || exit 1
        parted "${i}" --script mklabel msdos mkpart primary ext4 0% 100% || exit 1
        # Leave mkfs defaults, permutations to test:
        # -b block-size [512 | 1024 | 2048 | 4096]
        # [-i bytes-per-inode] [-I inode-size]
        mkfs.ext4 -F "${i}"  # TBD: -o agblksize={ 512 | 1024 | 2048 | 4096 } || exit 1
        echo "${i}    /${sizen} ext4  defaults,noatime        0 0" >>/etc/fstab
        mount "${i}" || mount -o remount "${i}"
    fi
done
