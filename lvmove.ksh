#!/usr/bin/ksh
## Lvmove script 
## Belal Koura SSNC
## Units in bytes  
## VERSION 2
#====================================================================================================
# VARs
pttrn=$1
lv_name="lv$1"
lv_vg=$(lvs --noheadings --nosuffix|grep $lv_name|awk '{print $2}')
max_vg=$(vgs --noheadings -o vg_name --sort vg_free|tail -1|xargs -n1) 
lv_size=$(lvs --noheadings --nosuffix --units B|grep $lv_name|awk '{print $4}') ## G
max_free=$(vgs --noheadings -o vg_free --units B --sort vg_free --nosuffix|tail -1|xargs -n1) ## G
#====================================================================================================
# Pre-checks 
if [[ -z "$1" || $EUID -ne 0 ]]; then
   echo "[INFO] Usage $0 <pattern>"
   exit 1
fi

#====================================================================================================
## Max_VG Not the same VG and Max_free not zero  
if (( `echo "$lv_size > $max_free || $max_free == 0" | bc -l` )) || [ "$lv_vg" == "$max_vg" ] ; then

echo "[ERROR] Volume group $max_vg has insufficient free space ${max_free}G: ${lv_size}G required."
exit 2

fi

#====================================================================================================
umount /$1 2> /dev/null 
lvcreate -L ${lv_size}B --name $lv_name $max_vg && \
dd if=/dev/${lv_vg}/${lv_name} of=/dev/${max_vg}/${lv_name}  bs=1024K conv=noerror,sync status=progress && \
lvremove /dev/${lv_vg}/${lv_name}

#====================================================================================================
if lvs /dev/${max_vg}/${lv_name} >/dev/null 2>&1 ; then
   if grep -q "$lv_name" /etc/fstab; then
   cpdate /etc/fstab
   sed -i "s/$lv_vg/$max_vg/g" /etc/fstab
   systemctl daemon-reload
   mount /$1
   fi 
fi
