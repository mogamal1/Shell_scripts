#!/usr/bin/ksh
## Account creation script
### Belal Koura SSNC 

#============================================================================================
# VARs
pttrn=$1
desired_size=$((($2+800/2)/800))
user_id=$3
grp_id=$4
f_port=$5
vg_list=$(vgdisplay -c | cut -d':' -f1)
lv_name="lv$1"
services=("tomcat_http" "tomcat_shut" "mq" "websphere_http" "websphere_jsp" "client" "broadcast" "rfnfy")


#============================================================================================
if [[ -z "$1" || -z "$2" || -z "$5"||  $EUID -ne 0 || `grep -q "^.*:x:$user_id:" /etc/passwd; echo $?` -eq 0 || `grep -q "^.*:x:$grp_id:" /etc/group; echo $?` -eq 0 ]]; then
   echo "[ERROR] User/Group already exists ... EXIT"
   echo "[INFO] Usage $0 <pattern> <size_in_SR> <UID> <GUID> <First_PORT>"
   exit 1
fi

#============================================================================================
# Adding ports/services in /etc/services
echo "[INFO] Backing up /etc/services"
cpdate /etc/services
echo "[INFO] Automating port mapping for $f_port ..."

if [ -z "$f_port" ]; then
  echo "[ERROR] port is not defined. Exiting without making any changes."
  exit 500
fi

echo "### By automation ###"                       >> /etc/services
for i in {0..7}; do
  port=$((f_port + i))
  service=${services[i]}
  ## Check if the port is already in use
  if grep -q "$port/tcp" /etc/services; then
    # Hash out the existing port
    echo "[Warning] Port $port already exists, it will be hashed"
    sed -i "/$port\/tcp/s/^/# /" /etc/services
  fi
  echo "${pttrn}_${service}            ${port}/tcp" >> /etc/services
done
echo "### end of automation ###"                   >> /etc/services

echo "[INFO] New added ports/services listed below:"
tail /etc/services

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
/dev/mapper/$vg_name-$lv_name              /$1                ext4    defaults        1 2
EOF

   fi
   systemctl daemon-reload
   mount /$1
   df -h /$1

fi
