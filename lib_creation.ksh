#!/usr/bin/ksh
## Libraries creation script
### Belal Koura SSNC 

#============================================================================================
# VARs
highest=$(ls -d /taliblnx* | sort -V | tail -n 1 | sed 's/\/taliblnx//')
next=$((highest + 1))
dir_name=taliblnx${1:-$next}
lv_name=lvtalb${1:-$next}
desired_size=${2:-18}
usr_name=${3:-tav62adm}
vg_list=$(vgdisplay -c | cut -d':' -f1)

#============================================================================================
if [[ $EUID -eq 0 && -z "$1" ]]; then
   echo "[INFO] Running $0 in automation mode ..."
   echo "[INFO] $0 <taliblnx#> <size_in_G> <lib_user_name> "
   echo "[INFO] user: $usr_name  size: ${desired_size}G dir_name: $dir_name "
elif [[ $EUID -ne 0 || -z "$1" || -z "$2" || -z "$3" ]] ; then 
   echo "[ERROR] please run the script with all arguments as below: "
   echo "[INFO] $0 <taliblnx#> <size_in_G> <lib_user_name> "
   exit 1
else 
   echo "[INFO] Running $0 in manual mode ... "
   echo "[INFO] $0 <taliblnx#> <size_in_G> <lib_user_name> "
   echo "[INFO] user: $usr_name size: ${desired_size}G dir_name: $dir_name "
fi

#============================================================================================
#============================================================================================
# Get the list of volume groups
for vg_name in $vg_list; do
    free_space=$(vgs --noheadings -o vg_free --units g $vg_name |tr -d ' '|sed 's/g//')
    if [ "$free_space" ]; then
        if [ `echo "$free_space > $desired_size"|bc` -eq 1 ]; then
            echo "[INFO] Selected VG: $vg_name (Free space: ${free_space}G) meets the criteria."
            echo "[INFO] Creating LV $lv_name with size ${desired_size}G..."
            lvcreate -L ${desired_size}G -n $lv_name $vg_name
            mkfs.ext4 -F /dev/$vg_name/$lv_name

            break  # Exit the loop after selecting the first suitable VG
        else
            echo "[Warning] VG $vg_name does not have sufficient free space. Trying the next one..."
        fi
    else
        echo "[ERROR] Unable to retrieve free space information for VG $vg_name."
    fi
done


#============================================================================================
# Verification steps 
if lvdisplay /dev/"$vg_name"/"$lv_name" >/dev/null 2>&1 ; then
   echo "[INFO] Backing up /etc/fstab"
   mkdir /$1
   cpdate /etc/fstab
   if [  `grep -cw $1 /etc/fstab` -eq 0 ] ; then
cat << EOF >> /etc/fstab
/dev/mapper/$vg_name-$lv_name              /dir_name                ext4    defaults        1 2
EOF

   fi
   systemctl daemon-reload
   mount /$1
   chown ${usr_name}:${usr_name} /dir_name
   df -h /$1

fi
