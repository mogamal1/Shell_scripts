#!/bin/bash
### Cloud init script for Golden Image Creation 
### Belal Koura SSNC
## Beta Version 

set -euo pipefail

LOG=/var/log/cloud-init-custom.log
exec > >(tee -a ${LOG}) 2>&1

echo "===== Cloud init started ====="

###################################
# 1. OS prep 
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
# Force local group only (no ldap/sss issues)
sed -i 's/^group:.*/group:  files/' /etc/nsswitch.conf

###################################
# 3. Directories
###################################
mkdir -p /bbtr
mkdir -p /opt/mqm /var/mqm
mkdir -p /u001 /u002 /u003
mkdir -p /opt/install

###################################
# 4. Groups
###################################
groupadd -g 209 tmgrbbtr || true
groupadd -g 182 oinstall || true
groupadd -g 180 dba || true
groupadd -g 488 fuse || true
groupadd -g 18 dialout || true

###################################
# 5. Users
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
# 6. Ownership
###################################
chown -R tmgrbbtr:tmgrbbtr /bbtr
chown -R mqm:mqm /opt/mqm /var/mqm

###################################
# 7. Java 8
###################################
dnf -y install java-1.8.0-openjdk java-1.8.0-openjdk-devel

JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))
cat <<EOF >/etc/profile.d/java.sh
export JAVA_HOME=${JAVA_HOME}
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
chmod +x /etc/profile.d/java.sh

###################################
# 8. Oracle prereqs (no EPEL needed)
###################################

#dnf -y install oracle-database-preinstall-19c || true

###################################
# 9. LVM provisioning (example /u001)
###################################
DISK=/dev/sdb
VG=vg_oracle
LV=lv_u01
MP=/u001

while [ ! -b "$DISK" ]; do
  echo "Waiting for $DISK..."
  sleep 5
done

pvs "$DISK" &>/dev/null || pvcreate "$DISK"
vgdisplay "$VG" &>/dev/null || vgcreate "$VG" "$DISK"
lvdisplay "/dev/$VG/$LV" &>/dev/null || lvcreate -n "$LV" -l 100%FREE "$VG"
blkid "/dev/$VG/$LV" &>/dev/null || mkfs.xfs -f "/dev/$VG/$LV"

mkdir -p "$MP"
grep -q "$LV" /etc/fstab || \
  echo "/dev/$VG/$LV $MP xfs defaults,nofail 0 2" >> /etc/fstab

mount "$MP" || mount -a
chown oracle:oinstall "$MP"

###################################
# 10. Final checks
###################################
grep '^group:' /etc/nsswitch.conf
df -h
id oracle
id mqm

echo "===== Cloud init completed successfully ====="
