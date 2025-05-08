#!/bin/ksh

# VARs
desired_size=$2
user_id=$3
grp_id=$4
vg_list=$(vgdisplay -c | cut -d':' -f1)
lv_name="lv$1"


if [[ -z "$1" ||  $EUID -ne 0 || `grep -q "^.*:x:$user_id:" /etc/passwd; echo $?` -eq 0 || `grep -q "^.*:x:$grp_id:" /etc/group; echo $?` -eq 0 ]]; then
   echo "User/Group already exists ... EXIT"
   echo "Usage ./$0 <pattern> <size_in_GB> <UID> <GUID>"
   exit 1
fi

echo "Backing up /etc/services"
cpdate /etc/services
echo "Please vi /etc/services and add the custom ports manually"


# Get the list of volume groups
for vg_name in $vg_list; do
    free_space=$(vgs --noheadings -o vg_free --units g $vg_name |tr -d ' '|sed 's/g//')
    if [ "$free_space" ]; then
        if [ `echo "$free_space > $desired_size"|bc` -eq 1 ]; then 
            echo "Selected VG: $vg_name (Free space: ${free_space}G) meets the criteria."
            echo "Creating LV $lv_name with size ${desired_size}G..."
            lvcreate -L ${desired_size}G -n $lv_name $vg_name
            mkfs.ext4 -F /dev/$vg_name/$lv_name

            break  # Exit the loop after selecting the first suitable VG
        else
            echo "VG $vg_name does not have sufficient free space. Trying the next one..."
        fi
    else
        echo "Error: Unable to retrieve free space information for VG $vg_name."
    fi
done


## Please try cpdate command first with full path
if lvdisplay /dev/"$vg_name"/"$lv_name" >/dev/null 2>&1 ; then
   echo "Backing up /etc/fstab"
   mkdir /$1
   cpdate /etc/fstab
   if [  `grep -cw $1 /etc/fstab` -eq 0 ] ; then
cat << EOF >> /etc/fstab
/dev/mapper/$vg_name-$lv_name              /$1                ext4    defaults        1 2
EOF
 
   fi 
   systemctl daemon-reload 
   mount /$1
   df -h /$1

fi
