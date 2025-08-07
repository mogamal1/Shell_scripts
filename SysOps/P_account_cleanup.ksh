#!/usr/bin/ksh
## Account cleanup script
## script handles only one account cleanup
### Belal Koura SSNC
## VERSION 6.11
#====================================================================================================
# VARs
pttrn=$1
lv_ptrrn="lv$1"
lv_name=$(lvdisplay -c|awk -F: -v x="$lv_ptrrn" '$1 ~ x {print $1}')

if [ -z "$lv_name" ]; then
    echo "[INFO] No LVs found with pattern '$lv_ptrrn', trying alternative detection..."
    lv_name=$(df -h /$pttrn 2>/dev/null | awk '$NF ~ /^\/'"$pttrn"'$/ {sub("/dev/mapper/","",$1); print $1}')
    
    if [ -z "$lv_name" ]; then
        lv_name=$(blkid | grep "$pttrn" | awk -F: '{print $1}')
    fi
    
    if [ -z "$lv_name" ]; then
        echo "[WARNING] Could not identify any LVs for pattern '$pttrn'"
        exit 44
    else
        echo "[INFO] Found LVs: $lv_name"
    fi
fi
#====================================================================================================
if [[ $EUID -eq 0 && -z "$1" ]]; then
    echo "[ERROR] Please run $0 <Account pattern> as root ... EXIT"
    echo "[INFO] Usage $0 <pattern to be removed>"
    exit 1
fi

echo "${lv_name}"
echo -n "Are you sure you want to remove the above logical volumes? (y/n)"
read confirmation
if [[ ! "$confirmation" =~ ^[Yy] ]]; then
    echo "[INFO] Aborted by user."
    exit 2
fi

#====================================================================================================
# Backup /etc/passwd with date and minutes
echo "[INFO] Backing up /etc/passwd"
cpdate /etc/passwd

# Removing entries containing '$pttrn' from /etc/passwd
echo "[INFO] Removing '$pttrn' entries from /etc/passwd"
awk -F: -v pattern="$pttrn" '$1 ~ pattern {print $1}' /etc/passwd|xargs -I {} echo User {} will be deleted ...
awk -F: -v pattern="$pttrn" '$1 ~ pattern {print $1}' /etc/passwd | xargs -I {} userdel {}
#sed -i "/^$pttrn/d" /etc/passwd

# Backup /etc/group with date and minutes
echo "[INFO] Backing up /etc/group"
cpdate /etc/group

# Removing entries containing '$pttrn' from /etc/group
echo "[INFO] Removing '$pttrn' entries from /etc/group"
sed -i "/^mqm:/s/$pttrn,//;/^mqm:/s/,$pttrn//" /etc/group
groupdel tmgr${pttrn}

# Printing mqm group
echo "[INFO] Printing existing users under 'mqm' group "
grep mqm /etc/group

# Backup /etc/services with date and minutes
echo "[INFO] Backing up /etc/services"
cpdate /etc/services

# Removing entries containing '$pttrn' from /etc/services
echo "[INFO] Removing '$pttrn' entries from /etc/services"
sed -i "/^$pttrn/d" /etc/services
#====================================================================================================
# Check if /$pttrn is mounted and unmount it
echo "[INFO] Unmounting Logical Volume ${lv_name}"
if df -h /$pttrn | grep -q $pttrn; then
    echo "Unmounting  /${pttrn}"
    # Check for processes using the mount point
    if fuser -vm /$pttrn 2>/dev/null; then
        echo "[WARNING] Processes using /$pttrn - attempting to kill them..."
        fuser -km /$pttrn
        sleep 2
    fi
    # Try regular unmount first, then lazy if that fails
    if ! umount /$pttrn; then
        echo "[INFO] Regular unmount failed, trying lazy unmount..."
        umount -l /$pttrn
    fi
fi

# Removing Logical Volume /dev/mapper/vg_lnxm06_5-lv$pttrn
echo "[INFO] Removing Logical Volume/s ${lv_name}"
for lv in $lv_name; do
    if ! lvremove -f $lv; then
        echo "[WARNING] Failed to remove $lv - it may still be in use"
        echo "[INFO] You can try manually with: lvremove -f $lv"
    fi
done

# Backup /etc/fstab with date and minutes
echo "[INFO] Backing up /etc/fstab"
cpdate /etc/fstab
echo "[INFO] Removing '$pttrn' entries from /etc/fstab"
sed -i "/$pttrn/d" /etc/fstab
# Only run systemctl if it exists
command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload
#====================================================================================================
# Check and remove /$pttrn directory
if [ -e "/$pttrn" ]; then
    echo "[INFO] Listing and removing /${pttrn} directory"
    ls -lsd /$pttrn*

    find / -maxdepth 1 -name "${pttrn}*" -type l -exec rm -v {} \; 2>/dev/null

    if ! rm -rf /$pttrn; then
        echo "[WARNING] Could not remove /$pttrn - it may still be in use"
        echo "[INFO] Check for processes using it: lsof /$pttrn"
    fi
fi
