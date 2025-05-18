#!/usr/bin/ksh
## Account creation script
### Belal Koura SSNC 
### Version 5.61
#=============================================================================================
# Set strict error handling
#set -euo pipefail
export LVM_SUPPRESS_FD_WARNINGS=1

# Global variables
pttrn=$1
input_size=$2
user_id=$3
grp_id=$4
f_port=$5
vg_list=$(vgdisplay -c | cut -d':' -f1)
lv_name="lv$1"
selected_vg=""
services=("tomcat_http" "tomcat_shut" "mq" "websphere_http" "websphere_jsp" "client" "broadcast" "rfnfy")
LOG_FILE="/tmp/account_creation_${pttrn}_$(date +%Y%m%d).log"

#=============================================================================================
# Function to log messages
log_message() {
    message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

#=============================================================================================
# Function to check input validation
validate_inputs() {

    if [[ "$input_size" =~ [Gg]$ ]]; then
        desired_size=${input_size%[Gg]}
    else
        desired_size=$((($input_size + 800 / 2) / 800))  # Convert SR to GB
    fi

    if [[ -z "$pttrn" || "$desired_size" -le 0 || -z "$f_port" || "$(id -u)" -ne 0 || `grep -q "^.*:x:$user_id:" /etc/passwd; echo $?` -eq 0 || `grep -q "^.*:x:$grp_id:" /etc/group; echo $?` -eq 0 ]]; then
        log_message "[ERROR] Please check script inputs and UID/GID"
        log_message "[INFO] Usage $0 <pattern> <size in SR|size in G> <UID> <GUID> <First_PORT>"
        exit 1
    fi

    if ! [[ "$input_size" =~ ^[0-9]+[Gg]?$ ]]; then
        log_message "[ERROR] Invalid size: '$input_size'. Use '1234' (SR) or '123G' (GB)."
        exit 1
    fi

    if [ -d "/${pttrn}" ]; then
        log_message "[ERROR] Pattern /${pttrn} already exists"
        exit 1
    fi
    
        log_message "[INFO] Account size is ${desired_size}G"
        log_message "[INFO] Starting account creation in 5 seconds..."
        sleep 5
}

#=============================================================================================
# Function to backup and update /etc/services with port mappings
update_services() {
    log_message "[INFO] Backing up /etc/services"
    cpdate /etc/services
    log_message "[INFO] Mapping ports for $pttrn (base_port: $f_port) ..."

    echo "### $pttrn services ###" >> /etc/services
    for i in "${!services[@]}"; do
        port=$((f_port + i))
        service=${services[i]}
        label="${pttrn}_${service}"

        if grep -q "$port/tcp" /etc/services; then
            log_message "[Warning] Port $port already exists."
        else
            printf '%-32s %s\n' "$label" "${port}/tcp" >> /etc/services
                        log_message "[DEBUG] Mapped $label to $port/tcp"
                fi
        echo "#" >> /etc/services
    done
}

#=============================================================================================
# Function to prompt for additional groups and their port mappings
add_groups_to_services() {
    read n_groups?"Enter number of additional groups (0 to skip): "

    if [ "$n_groups" -eq 0 ]; then
        log_message "[INFO] No additional groups to add."
        return
    fi

    for ((g=1; g<=n_groups; g++)); do
        read gid?"Enter GID for group ${pttrn}grp${g}: "
        read grp_port?"Enter starting port for group ${pttrn}grp${g}: "

        if grep -q "^.*:x:$gid:" /etc/group; then
           log_message "[WARNING] GID $gid exists (will be reused)"
        fi

        for i in "${!services[@]}"; do
            port=$((grp_port + i))
            service=${services[i]}
            label="${pttrn}grp${g}_${service}"

            if grep -q "$port/tcp" /etc/services; then
                log_message "[Warning] ${pttrn}grp${g} Port $port already exists."
                        else
                printf '%-32s %s\n' "$label" "${port}/tcp" >> /etc/services
                    fi
        done
        echo "#" >> /etc/services
    done
    echo "### end of automation ###" >> /etc/services
}

#=============================================================================================
# Function to create logical volume
create_lv() {
    echo "$vg_list" | while read -r vg_name; do
        free_space=$(vgs --noheadings -o vg_free --units g $vg_name | tr -d ' ' | sed 's/g//')
        if [ "$free_space" ]; then
            if [ `echo "$free_space > $desired_size" | bc` -eq 1 ]; then
                log_message "[INFO] Selected VG: $vg_name (Free space: ${free_space}G) meets the criteria."
                log_message "[INFO] Creating LV $lv_name with size ${desired_size}G..."
                selected_vg=$vg_name
                lvcreate -Wy --yes -L ${desired_size}G -n $lv_name $vg_name || { log_message "[ERROR] LV creation failed"; exit 1; }
                mkfs.ext4 -F /dev/$vg_name/$lv_name
                return 0
            else
                log_message "[Warning] VG $vg_name does not have sufficient free space. Trying the next one..."
            fi
        else
            log_message "[ERROR] Unable to retrieve free space information for VG $vg_name."
        fi
    done

    log_message "[ERROR] No VG found with sufficient free space (required: ${desired_size}G)"
    return 1
}

#=============================================================================================
# Function to update /etc/fstab and mount the LV
setup_filesystem() {
    if [[ -n "$selected_vg" ]] && lvs "/dev/$selected_vg/$lv_name" &>/dev/null ; then
        log_message "[INFO] Backing up /etc/fstab"
        mkdir -p "/$pttrn" || { log_message "[ERROR] Cannot create /$pttrn"; return 1; }
        cpdate /etc/fstab
        if [ `grep -cw $pttrn /etc/fstab` -eq 0 ] ; then
            cat << EOF >> /etc/fstab
/dev/mapper/$selected_vg-$lv_name              /$pttrn                ext4    defaults        1 2
EOF
        fi
        mount "/$pttrn" || { log_message "[ERROR] Mount failed"; return 1; }
        df -h "/$pttrn" | tee -a "$LOG_FILE"
    fi
}

#=============================================================================================
#### Main Code ####

validate_inputs
update_services
add_groups_to_services
log_message "[INFO] New added ports/services for $pttrn listed below:"
grep "$pttrn" /etc/services | tee -a "$LOG_FILE"
if create_lv; then
    if setup_filesystem ; then
       log_message "[SUCCESS] Account $pttrn created successfully"
    else 
       log_message "[FAILED] mountpoint /$pttrn not created - Account creation incomplete"
    fi 
else
    log_message "[FAILED] cannot create LV lv$pttrn - Account creation incomplete"
    exit 1
fi