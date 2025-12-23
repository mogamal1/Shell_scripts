#!/bin/bash
### Cloud init script for Golden Image Creation 
### Belal Koura SSNC
## Beta Version 

set -euo pipefail

LOG=/var/log/cloud-init-custom.log
exec > >(tee -a ${LOG}) 2>&1

echo "===== Cloud init started ====="

###################################
# 1. OS Packages prep 
###################################
dnf -y update
dnf -y install \
    ksh \
    unzip \
    tar \
    wget \
    tmux \
    openssh-server \
    sudo \
    which \
    net-tools \
    glibc \
    glibc-devel \
    libaio \
    libaio-devel \
    compat-libstdc++ \
    gcc \
    make \
    lvm2

systemctl enable sshd
systemctl restart sshd

###################################
# 2. NSSWITCH FIX 
###################################
# Force local group authentication only (no ldap/sss)
sed -i 's/^group:.*/group:  files/' /etc/nsswitch.conf

###################################
# 3. SECURITY LIMITS (Oracle + MQ)
###################################

LIMITS_FILE=/etc/security/limits.conf

add_limit() {
  local entry="$1"
  grep -qF "$entry" "$LIMITS_FILE" || echo "$entry" >> "$LIMITS_FILE"
}

# Oracle limits
add_limit "oracle soft nproc 2047"
add_limit "oracle hard nproc 16384"
add_limit "oracle soft nofile 4096"
add_limit "oracle hard nofile 65536"
add_limit "oracle soft stack 10240"
add_limit "oracle hard stack 10240"

# MQ limits
add_limit "mqm hard nofile 10240"
add_limit "mqm soft nofile 524288"

###################################
# 4. Directories
###################################
mkdir -p /bbtr
mkdir -p /opt/mqm /var/mqm
mkdir -p /u001 /u002 /u003
mkdir -p /opt/install

###################################
# 5. Groups
###################################
groupadd -g 209 tmgrbbtr || true
groupadd -g 182 oinstall || true
groupadd -g 180 dba || true
groupadd -g 488 fuse || true
groupadd -g 18 dialout || true

###################################
# 6. Users
###################################
useradd -m mqm || true
usermod -aG mqm mqm

useradd -u 2090 -g 209 -m -d /bbtr/traders/tmgrbbtr -s /usr/bin/ksh tmgrbbtr || true
usermod -aG mqm tmgrbbtr

for i in 1 2 3 4 5; do
  useradd -u $((2090 + i)) -g 209 -m \
    -d /bbtr/traders/t${i}bbtr \
    -s /usr/bin/ksh t${i}bbtr || true
done

useradd -u 180 -g oinstall -G dba -m -s /usr/bin/ksh oracle || true
usermod -aG fuse oracle

###################################
# 7. Ownership
###################################
chown -R tmgrbbtr:tmgrbbtr /bbtr
chown -R mqm:mqm /opt/mqm /var/mqm

###################################
# 8. Java 8
###################################
dnf -y install java-1.8.0-openjdk java-1.8.0-openjdk-devel

JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
cat <<EOF >/etc/profile.d/java.sh
export JAVA_HOME=${JAVA_HOME}
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
chmod +x /etc/profile.d/java.sh

###################################
# 9. Oracle prereqs 
###################################

#dnf -y install oracle-database-preinstall-19c || true

#####################################
# 10. LVM provisioning 
#####################################
create_lvm() {
  local DISK="$1"
  local VG="$2"

  if [ ! -b "$DISK" ]; then
    echo "INFO: $DISK not present. Skipping VG $VG."
    return 0
  fi

  pvs "$DISK" &>/dev/null || pvcreate "$DISK"
  vgdisplay "$VG" &>/dev/null || vgcreate "$VG" "$DISK"
}

create_lv_fs() {
  local VG="$1"
  local LV="$2"
  local SIZE="$3"
  local MP="$4"

  lvdisplay "/dev/$VG/$LV" &>/dev/null || lvcreate -n "$LV" -L "$SIZE" "$VG"
  blkid "/dev/$VG/$LV" &>/dev/null || mkfs.xfs -f "/dev/$VG/$LV"

  mkdir -p "$MP"
  grep -q "/dev/$VG/$LV" /etc/fstab || \
    echo "/dev/$VG/$LV $MP xfs defaults,nofail 0 2" >> /etc/fstab

  mount "$MP" || mount -a
}

###################################
# VG: vg_lnxm12_2  (/dev/sdc)
###################################
create_lvm /dev/sdc vg_lnxm12_2

if vgdisplay vg_lnxm12_2 &>/dev/null; then
  lvdisplay /dev/vg_lnxm12_2/lvu002 &>/dev/null || \
    lvcreate -n lvu002 -l 100%FREE vg_lnxm12_2

  blkid /dev/vg_lnxm12_2/lvu002 &>/dev/null || \
    mkfs.xfs -f /dev/vg_lnxm12_2/lvu002

  mkdir -p /u002
  grep -q lvu002 /etc/fstab || \
    echo "/dev/vg_lnxm12_2/lvu002 /u002 xfs defaults,nofail 0 2" >> /etc/fstab

  mount /u002 || mount -a
  chown oracle:oinstall /u002
fi

###################################
# VG: vg_lnxm12_3  (/dev/sdb)
###################################
create_lvm /dev/sdb vg_lnxm12_3

if vgdisplay vg_lnxm12_3 &>/dev/null; then
  create_lv_fs vg_lnxm12_3 lvu001 100G /u001
  create_lv_fs vg_lnxm12_3 lvu003 296G /u003
  create_lv_fs vg_lnxm12_3 lvbbtr 15G  /bbtr

  # Swap
  lvdisplay /dev/vg_lnxm12_3/swap &>/dev/null || \
    lvcreate -n swap -L 30G vg_lnxm12_3

  mkswap /dev/vg_lnxm12_3/swap || true
  swapon /dev/vg_lnxm12_3/swap || true
  grep -q vg_lnxm12_3/swap /etc/fstab || \
    echo "/dev/vg_lnxm12_3/swap swap swap defaults 0 0" >> /etc/fstab

  chown oracle:oinstall /u001 /u002 /u003
  chown tmgrbbtr:tmgrbbtr /bbtr
fi

###################################
# 11. Final checks
###################################
grep '^group:' /etc/nsswitch.conf
df -h
id oracle
id mqm

echo "===== Cloud init completed successfully ====="
