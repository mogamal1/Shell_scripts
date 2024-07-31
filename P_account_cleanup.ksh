#!/usr/bin/ksh
## Account cleanup script
## script handle only one account cleanup 
### Belal Koura SSNC 
## VERSION 3 
#====================================================================================================
# VARs
pttrn=$1
lv_ptrrn="lv$1"
lv_name=$(lvdisplay -c|awk -F: -v x="$lv_ptrrn" '$1 ~ x {print $1}')

#====================================================================================================
if [[ $EUID -eq 0 && -z "$1" ]]; then
   echo "[ERROR] Please run $0 <Account pattern> as root ... EXIT"
   exit 1 
fi

echo "${lv_name}"
echo -n "Are you sure you want to remove logical volumes? (y/n)" 
read confirmation
if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
   echo "[INFO] Aborted by user."
   exit 2
fi

#====================================================================================================
# Backup /etc/passwd with date and minutes
echo "[INFO] Backing up /etc/passwd"
cpdate /etc/passwd

# Removing entries containing '$pttrn' from /etc/passwd
echo "[INFO] Removing '$pttrn' entries from /etc/passwd"
awk -F: '/$pttrn/ {print $1}' /etc/passwd | xargs -I {} userdel {}
sed -i "/$pttrn/d" /etc/passwd

# Backup /etc/group with date and minutes
echo "[INFO] Backing up /etc/group"
cpdate /etc/group

# Removing entries containing '$pttrn' from /etc/group
echo "[INFO] Removing '$pttrn' entries from /etc/group"
sed -i "/$pttrn/d" /etc/group

# Backup /etc/services with date and minutes
echo "[INFO] Backing up /etc/services"
cpdate /etc/services

# Removing entries containing '$pttrn' from /etc/services
echo "[INFO] Removing '$pttrn' entries from /etc/services"
sed -i "/$pttrn/d" /etc/services
#====================================================================================================
# Check if /$pttrn is mounted and unmount it
echo "[INFO] Unmounting Logical Volume ${lv_name}"
df -h /$pttrn | grep $pttrn && echo "Unmounting /${pttrn}" && umount /$pttrn
# Removing Logical Volume /dev/mapper/vg_lnxm06_5-lv$pttrn
echo "[INFO] Removing Logical Volume/s ${lv_name}"
lvremove -f $lv_name
# Backup /etc/fstab with date and minutes
echo "[INFO] Backing up /etc/fstab"
cpdate /etc/fstab
echo "[INFO] Removing '$pttrn' entries from /etc/fstab"
sed -i "/$pttrn/d" /etc/fstab
systemctl daemon-reload
#====================================================================================================
# Check and remove /$pttrn directory
if [ -e "/$pttrn" ]; then
   echo "[INFO] Listing and removing /${pttrn} directory"
   ls -lsd /$pttrn*
   find / -maxdepth 1 -name "${pttrn}*" -type l -exec rm -v {} \; 
   rm -rfv /$pttrn
fi
