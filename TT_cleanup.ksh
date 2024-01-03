#!/bin/ksh

# Backup /etc/passwd with date and minutes
backup_file="/etc/passwd.bkp.$(date +%d%m%y%H%M)"
echo "Backing up /etc/passwd to $backup_file"
cp /etc/passwd "$backup_file"

# Remove entries containing 'bnlt' from /etc/passwd
echo "Removing 'bnlt' entries from /etc/passwd"
sed -i "/bnlt/d" /etc/passwd

# Backup /etc/group with date and minutes
backup_file="/etc/group.bkp.$(date +%d%m%y%H%M)"
echo "Backing up /etc/group to $backup_file"
cp /etc/group "$backup_file"

# Remove entries containing 'bnlt' from /etc/group
echo "Removing 'bnlt' entries from /etc/group"
sed -i "/bnlt/d" /etc/group

# Backup /etc/services with date and minutes
backup_file="/etc/services.bkp.$(date +%d%m%y%H%M)"
echo "Backing up /etc/services to $backup_file"
cp /etc/services "$backup_file"

# Remove entries containing 'bnlt' from /etc/services
echo "Removing 'bnlt' entries from /etc/services"
sed -i "/bnlt/d" /etc/services

# Check if /bnlt is mounted and unmount it
df -h /bnlt | grep bnlt && echo "Unmounting /bnlt" && umount /bnlt

# Backup /etc/fstab with date and minutes
backup_file="/etc/fstab.bkp.$(date +%d%m%y%H%M)"
echo "Backing up /etc/fstab to $backup_file"
cp /etc/fstab "$backup_file"

# Remove entries containing 'bnlt' from /etc/fstab
echo "Removing 'bnlt' entries from /etc/fstab"
sed -i "/bnlt/d" /etc/fstab
done

# Remove Logical Volume /dev/mapper/vg_lnxm06_5-lvbnlt
echo "Removing Logical Volume /dev/mapper/vg_lnxm06_5-lvbnlt"
lvremove /dev/mapper/vg_lnxm06_5-lvbnlt

# Check and remove /bnlt directory
if [ -e "/bnlt" ]; then
    echo "Listing and removing /bnlt directory"
    ls -lsd /bnlt*
    rm -r /bnlt
fi

echo "Script execution complete."
