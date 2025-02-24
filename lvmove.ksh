#!/usr/bin/ksh
## Lvmove script
## Belal Koura SSNC
## Units in bytes
## VERSION 8
#==============================================================================================================
# Pre-checks
if [[ -z "$1" || $EUID -ne 0 ]]; then
   echo "[INFO] Usage $0 [OPTION] <lv_name|pattern>"
   echo "[INFO] OPTIONS"
   echo "[INFO] -f,  Override various checks, confirmations, and protections.  Use with extreme caution."
   exit 1
fi

#==============================================================================================================
# VARs
lvr_flag=nohints

for arg in "$@"; do
    case "$arg" in
        -f)
            lvr_flag=force
            ;;
        *)
            if [[ "$arg" =~ ^/dev/([^/]+)/([^/]+)$ ]]; then
                lv_name=${arg##*/}
		lv_vg=$(echo $arg|awk -F/ '{print $3}')
            else
                lv_name=$(lvs --noheadings -o lv_name | awk -v lv="$arg" '!seen[$1]++ && $1 ~ lv {print $1}')
		lv_vg=$(lvs --noheadings|awk -v lv="$lv_name" '!seen[$1]++ && $1==lv{print $2}')
            fi
            ;;
    esac
done

if [[ -z "$lv_name" ]]; then
    echo "[ERROR] Logical Volume (LV) name is empty or invalid system. Please run on LVM setup"
    exit 1
fi

lv_size=$(lvs --noheadings --nosuffix --units B|grep $lv_name|awk 'NR==1{print $4}') ## Size in Bytes
max_free=$(vgs --noheadings -o vg_free --units B --sort vg_free --nosuffix|awk 'END{print $1}') ## Size in Bytes
max_vg=$(vgs --noheadings -o vg_name --sort vg_free|awk 'END{print $1}')
dev_size=$(df /dev|awk 'NR==2{print $5}'|sed 's/%//')
completion_file="/usr/share/bash-completion/completions/lvmove"
install_file="/sbin/lvmove"

#==============================================================================================================
if [[ ! -f "$completion_file" || ! -f "$install_file" ]]; then
echo "[INFO] Creating Bash completion file for lvmove"

cat << EOF > $completion_file
# bash completion for lvm                                  -*- shell-script -*-
_lvmove()
{

    local cur_word="\${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=(\$(compgen -W "\$(lvscan 2>/dev/null|sed -n -e "s|^.*'\(.*\)'.*$|\1|p")" -- "\$cur_word"))
} &&
complete -F _lvmove lvmove
EOF

chmod 644 "$completion_file"
cp "$0" "$install_file" &&\
chmod +x "$install_file" &&\
echo "[INFO] $0 installed as lvmove tool, please rerun it as a command --> lvmove [OPTION] <lv_name|pattern>"
exit 30
fi

#==============================================================================================================
## Max_VG Not the same VG and Max_free not zero
## make sure devtmpfs is not full
if [[ "$dev_size" -lt 100 ]]; then
   if (( `echo "$lv_size > $max_free || $max_free == 0" | bc -l` )); then

    echo "[ERROR] Volume group $max_vg has insufficient free space ${max_free}B: ${lv_size}B required."
    exit 2
   
   elif [[ "$lv_vg" == "$max_vg" ]]; then 

    echo "[INFO] volume group $lv_vg is the same as the maximum volume group"
    exit 99
	
   fi

else
  echo "[ERROR] /dev has no free space"
  exit 100

fi
#==============================================================================================================
## copying data from old VG to new VG
grep -cq $lv_name /proc/mounts &&\
umount -f /dev/${lv_vg}/${lv_name} 2> /dev/null

lvcreate -L ${lv_size}B --name $lv_name $max_vg &&\
echo "[INFO] Please wait while copying $lv_name data to $max_vg ..." &&\
dd if=/dev/${lv_vg}/${lv_name} of=/dev/${max_vg}/${lv_name}  bs=1024K conv=noerror,sync status=progress &&\
lvremove --${lvr_flag} /dev/${lv_vg}/${lv_name}

#==============================================================================================================
if lvs /dev/${max_vg}/${lv_name} >/dev/null 2>&1 ; then
   if grep -q "$lv_name" /etc/fstab; then
     cp /etc/fstab{,_`date +%Y%m%d%H%M`}
     sed -i "s/\/dev\/mapper\/${lv_vg}-${lv_name}/\/dev\/mapper\/${max_vg}-${lv_name}/g" /etc/fstab
     systemctl daemon-reload &&\
     echo "[INFO] fstab file updated. "
     mount /dev/${max_vg}/${lv_name} 2> /dev/null
   fi
fi
