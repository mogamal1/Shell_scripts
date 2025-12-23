#!/bin/bash
###############################################################################
# Cloud-init user-data script for Golden Image / First-Boot Provisioning
# Belal Koura SSNC
# VERSION="1.3"
# ========================= PREREQUISITES  =====================================
#
# [A] Execution / cloud-init
#   - cloud-init must be enabled on the image/template.
#   - user-data runs as root
#   - This script is intended to run on first boot of a new instance.
#
# [B] OS/rootvg 
#   - The OS/root volume layout (rootvg and OS mountpoints like /, /var/log,
#     /var/tmp, /opt/traps, /tmp, /home, swap, etc.) must already exist
#     in the golden image/template OR be provisioned by your OS build pipeline.
#   - This script DOES NOT create/resize/modify rootvg.
#
#   - Recommended IaC prereq:
#       * Terraform provisions the VM using the
#         correct golden image/template that already includes the desired rootvg.
#
# [C] Data disks for LVM 
#   To reproduce the EXACT target LVM layout you provided, the instance must
#   have the following *empty* data disks attached BEFORE first boot:
#
#     1) ~300 GiB disk  -> vg_lnxm12_2 -> lvu002 (100%FREE) -> /u002 (ext4)
#     2) ~600 GiB disk  \
#     3) ~200 GiB disk   -> vg_lnxm12_3 (2 PVs) with LVs (ext4 unless swap):
#           - lvu001     100G  -> /u001
#           - lvu003     296G  -> /u003
#           - lvbbtr     15G   -> /bbtr
#           - lvttbckup  100G  -> /tt_backup
#           - lvtav62    20G   -> /tav62ln12
#           - lvdpdump   200G  -> /tt_dpdump
#           - swap       30G   -> swap
#
#   Notes:
#   - Disks must be EMPTY (no partition table / filesystems / old PVs).
#   - This script auto-detects disks by size + safety checks (it does not rely
#     on /dev/sdb ordering).
#   - If the required disks are not present on first boot, LVM provisioning is
#     SKIPPED safely.
#
# [D] SaltStack usage (optional)
#   - we can use it in one of two ways:
#     1) Cloud-init does provisioning (default), and Salt may do app configs later.
#     2) Salt is authoritative: cloud-init does minimal bootstrap, then triggers:
#          RUN_SALT=1  (and optionally SALT_ACTION/highstate)
#   - Prereq: salt-call must be installed and minion configuration must be
#     correct (master reachable OR local mode states available).
#
# [E] Installers from Box (MF COBOL / IBM MQ / Oracle DB)
#   - Box is used as the distribution source for installers.
#   - Prereq: A separate mechanism (pipeline, Terraform provisioner, Salt state,
#     or your private-cloud tooling) must download installers from Box and place
#     them under:
#        /opt/install
#
#   - This script will log which expected installer files are present/missing.
#   - Optional: set RUN_INSTALLERS=1 to attempt installs if installers exist.
#     (Keep RUN_INSTALLERS=0 for golden image or “baseline-only” builds.)
#
# =============================== LOGGING ====================================
#   - This script log to: /var/log/cloud-init-custom.log
#   - Cloud-ini default logs to:
#       /var/log/cloud-init.log
#       /var/log/cloud-init-output.log
###############################################################################

set -euo pipefail
umask 022

SCRIPT_NAME="ssnc-golden-init"
SCRIPT_VERSION="1.3"

# ---- Logging: everything into one file ----
CUSTOM_LOG="/var/log/cloud-init-custom.log"
mkdir -p "$(dirname "$CUSTOM_LOG")"
touch "$CUSTOM_LOG"
chmod 600 "$CUSTOM_LOG"

# Prefix each line with an ISO timestamp and tee into the custom log
exec > >(while IFS= read -r line; do printf '[%s] %s\n' "$(date -Is)" "$line"; done | tee -a "$CUSTOM_LOG") 2>&1

# Optional command tracing (WARNING: may expose tokens/URLs if you download installers)
DEBUG="${DEBUG:-0}"
if [[ "$DEBUG" == "1" ]]; then
  set -x
fi

trap 'echo "ERROR: rc=$? line=${BASH_LINENO[0]} cmd=${BASH_COMMAND}"' ERR
trap 'echo "===== ${SCRIPT_NAME} v${SCRIPT_VERSION} completed rc=$? ====="' EXIT

echo "===== ${SCRIPT_NAME} v${SCRIPT_VERSION} started ====="
echo "Custom log: ${CUSTOM_LOG}"
echo "Also check cloud-init logs: /var/log/cloud-init.log and /var/log/cloud-init-output.log"

###############################################################################
# 1) Packages + SSH
###############################################################################
RUN_DNF_UPDATE="${RUN_DNF_UPDATE:-0}"   # set 1 if you want full OS update
if [[ "$RUN_DNF_UPDATE" == "1" ]]; then
  echo "INFO: Running dnf update (RUN_DNF_UPDATE=1)"
  dnf -y update
else
  echo "INFO: Skipping dnf update (RUN_DNF_UPDATE=0)"
fi

echo "INFO: Installing required packages"
dnf -y install \
  ksh unzip tar wget tmux openssh-server sudo which net-tools \
  glibc glibc-devel libaio libaio-devel compat-libstdc++ \
  gcc make lvm2 e2fsprogs util-linux coreutils

systemctl enable --now sshd || true

###############################################################################
# 2) NSSWITCH FIX
###############################################################################
# Force local group resolution only (avoid ldap/sss delays)
if grep -q '^group:' /etc/nsswitch.conf; then
  cp -a /etc/nsswitch.conf /etc/nsswitch.conf.bak.$(date +%s) || true
  sed -i 's/^group:.*/group:  files/' /etc/nsswitch.conf
else
  echo 'group:  files' >> /etc/nsswitch.conf
fi
echo "INFO: nsswitch group line: $(grep '^group:' /etc/nsswitch.conf || true)"

###############################################################################
# 3) SECURITY LIMITS (Oracle + MQ)
###############################################################################
LIMITS_FILE=/etc/security/limits.conf
touch "$LIMITS_FILE"

add_limit() {
  local entry="$1"
  grep -qF "$entry" "$LIMITS_FILE" || echo "$entry" >> "$LIMITS_FILE"
}

# Oracle limits
add_limit "oracle soft nproc 2047"
add_limit "oracle hard nproc 16384"
add_limit "oracle soft nofile 4096"
add_limit "oracle hard nofile 65536"
add_limit "oracle soft stack 10240"
add_limit "oracle hard stack 10240"

# MQ limits 
add_limit "mqm hard nofile 10240"
add_limit "mqm soft nofile 524288"

###############################################################################
# 4) Base directories (mountpoints + install dirs)
###############################################################################
mkdir -p /opt/install /opt/mqm /var/mqm
mkdir -p /u001 /u002 /u003 /bbtr /tt_backup /tav62ln12 /tt_dpdump
mkdir -p /bbtr/traders

###############################################################################
# 5) LVM provisioning (AUTO-DETECT)
###############################################################################
# Controls:
STRICT_DISK_MATCH="${STRICT_DISK_MATCH:-0}"  # 1 = fail if multiple candidates for a size
DISK_TOL_PCT="${DISK_TOL_PCT:-3}"            # +/- tolerance percent for size matching

ROOT_SOURCE="$(findmnt -no SOURCE / || true)"
ROOT_DISK="$(lsblk -no PKNAME "$ROOT_SOURCE" 2>/dev/null | head -1 || true)"
echo "INFO: Root source: $ROOT_SOURCE | Root disk: /dev/${ROOT_DISK:-unknown}"

# Return candidate disks approx size (GiB), empty, not root, no children, no signatures
list_empty_disks_by_size_gib() {
  local target_gib="$1"
  local target_bytes=$(( target_gib * 1024 * 1024 * 1024 ))
  local min_bytes=$(( target_bytes * (100 - DISK_TOL_PCT) / 100 ))
  local max_bytes=$(( target_bytes * (100 + DISK_TOL_PCT) / 100 ))

  lsblk -dn -b -o NAME,SIZE,TYPE | awk '$3=="disk"{print $1" "$2}' | while read -r name bytes; do
    local dev="/dev/$name"

    [[ -n "${ROOT_DISK:-}" && "$dev" == "/dev/$ROOT_DISK" ]] && continue

    (( bytes < min_bytes || bytes > max_bytes )) && continue

    # skip if disk has children (partitions)
    [[ "$(lsblk -n -o NAME "$dev" | wc -l)" -gt 1 ]] && continue

    # skip if already PV
    pvs "$dev" &>/dev/null && continue

    # skip if any signatures
    wipefs -n "$dev" | grep -q . && continue

    echo "$dev"
  done
}

choose_one_disk() {
  local gib="$1"
  mapfile -t candidates < <(list_empty_disks_by_size_gib "$gib" || true)

  if (( ${#candidates[@]} == 0 )); then
    echo ""
    return 0
  fi

  if (( ${#candidates[@]} > 1 )); then
    echo "WARN: Multiple empty disks match ~${gib}GiB: ${candidates[*]}"
    if [[ "$STRICT_DISK_MATCH" == "1" ]]; then
      echo "ERROR: STRICT_DISK_MATCH=1 and multiple candidates found for ~${gib}GiB. Refusing to guess."
      exit 1
    fi
  fi

  echo "${candidates[0]}"
}

ensure_pv() { pvs "$1" &>/dev/null || pvcreate "$1"; }
ensure_vg_create() { vgdisplay "$1" &>/dev/null || vgcreate "$1" "$2"; }

ensure_vg_extend_if_needed() {
  local vg="$1" disk="$2"
  if [[ -n "$disk" ]] && ! pvs --noheadings -o vg_name "$disk" 2>/dev/null | awk '{print $1}' | grep -qx "$vg"; then
    vgextend "$vg" "$disk" || true
  fi
}

ensure_lv() { lvdisplay "/dev/$1/$2" &>/dev/null || lvcreate -n "$2" -L "$3" "$1"; }
ensure_lv_fullfree() { lvdisplay "/dev/$1/$2" &>/dev/null || lvcreate -n "$2" -l 100%FREE "$1"; }

ensure_ext4() {
  local dev="$1"
  local fstype
  fstype="$(blkid -o value -s TYPE "$dev" 2>/dev/null || true)"
  if [[ -z "$fstype" ]]; then
    mkfs.ext4 -F "$dev"
  elif [[ "$fstype" != "ext4" ]]; then
    echo "WARN: $dev has filesystem type=$fstype; not formatting."
  fi
}

fstab_add_once() {
  local line="$1"
  grep -qF "$line" /etc/fstab || echo "$line" >> /etc/fstab
}

mount_if_needed() {
  local mp="$1"
  mountpoint -q "$mp" || mount "$mp" || true
}

# Discover disks
DISK_300G="$(choose_one_disk 300)"
DISK_600G="$(choose_one_disk 600)"
DISK_200G="$(choose_one_disk 200)"

echo "INFO: Candidate data disks: 300G='${DISK_300G:-none}', 600G='${DISK_600G:-none}', 200G='${DISK_200G:-none}'"

# vg_lnxm12_2 (requires ~300GiB disk)
if vgdisplay vg_lnxm12_2 &>/dev/null || [[ -n "${DISK_300G:-}" ]]; then
  if ! vgdisplay vg_lnxm12_2 &>/dev/null; then
    echo "INFO: Creating vg_lnxm12_2 on $DISK_300G"
    ensure_pv "$DISK_300G"
    ensure_vg_create vg_lnxm12_2 "$DISK_300G"
  fi

  ensure_lv_fullfree vg_lnxm12_2 lvu002
  ensure_ext4 /dev/vg_lnxm12_2/lvu002

  fstab_add_once "/dev/mapper/vg_lnxm12_2-lvu002 /u002 ext4 defaults 1 2"
  systemctl daemon-reload || true
  mount_if_needed /u002
else
  echo "INFO: Missing ~300GiB disk. Skipping vg_lnxm12_2 (/u002)."
fi

# vg_lnxm12_3 (requires BOTH ~600GiB and ~200GiB disks for full layout)
if vgdisplay vg_lnxm12_3 &>/dev/null; then
  echo "INFO: vg_lnxm12_3 already exists. Ensuring LVs/mounts."
else
  if [[ -n "${DISK_600G:-}" && -n "${DISK_200G:-}" ]]; then
    echo "INFO: Creating vg_lnxm12_3 on $DISK_600G and extending with $DISK_200G"
    ensure_pv "$DISK_600G"
    ensure_pv "$DISK_200G"
    vgcreate vg_lnxm12_3 "$DISK_600G"
    vgextend vg_lnxm12_3 "$DISK_200G"
  else
    echo "INFO: Missing disks for full vg_lnxm12_3 layout (~600GiB + ~200GiB). Skipping vg_lnxm12_3 entirely."
  fi
fi

if vgdisplay vg_lnxm12_3 &>/dev/null; then
  # Create LVs (match your lvs output)
  ensure_lv vg_lnxm12_3 lvu001    100G
  ensure_lv vg_lnxm12_3 lvu003    296G
  ensure_lv vg_lnxm12_3 lvbbtr    15G
  ensure_lv vg_lnxm12_3 lvttbckup 100G
  ensure_lv vg_lnxm12_3 lvtav62   20G
  ensure_lv vg_lnxm12_3 lvdpdump  200G
  ensure_lv vg_lnxm12_3 swap      30G

  # Filesystems (ext4 as in your reference)
  ensure_ext4 /dev/vg_lnxm12_3/lvu001
  ensure_ext4 /dev/vg_lnxm12_3/lvu003
  ensure_ext4 /dev/vg_lnxm12_3/lvbbtr
  ensure_ext4 /dev/vg_lnxm12_3/lvttbckup
  ensure_ext4 /dev/vg_lnxm12_3/lvtav62
  ensure_ext4 /dev/vg_lnxm12_3/lvdpdump

  # fstab lines (match your reference)
  fstab_add_once "/dev/mapper/vg_lnxm12_3-lvu001 /u001 ext4 defaults 1 2"
  fstab_add_once "/dev/mapper/vg_lnxm12_3-lvu003 /u003 ext4 defaults 1 2"
  fstab_add_once "/dev/mapper/vg_lnxm12_3-lvbbtr /bbtr ext4 defaults 1 2"
  fstab_add_once "/dev/vg_lnxm12_3/lvttbckup /tt_backup ext4 defaults 1 2"
  fstab_add_once "/dev/vg_lnxm12_3/lvtav62 /tav62ln12 ext4 defaults 1 2"
  fstab_add_once "/dev/vg_lnxm12_3/lvdpdump /tt_dpdump ext4 defaults 1 2"
  fstab_add_once "/dev/mapper/vg_lnxm12_3-swap none swap defaults 0 0"

  systemctl daemon-reload || true

  mount_if_needed /u001
  mount_if_needed /u003
  mount_if_needed /bbtr
  mount_if_needed /tt_backup
  mount_if_needed /tav62ln12
  mount_if_needed /tt_dpdump

  mkswap /dev/vg_lnxm12_3/swap || true
  swapon /dev/vg_lnxm12_3/swap || true
fi

###############################################################################
# 6) Groups
###############################################################################
groupadd -g 209 tmgrbbtr || true
groupadd -g 182 oinstall || true
groupadd -g 180 dba || true
groupadd -g 488 fuse || true
groupadd -g 18 dialout || true

###############################################################################
# 7) Users
###############################################################################
useradd -m mqm || true
usermod -aG mqm mqm || true

useradd -u 2090 -g 209 -m -d /bbtr/traders/tmgrbbtr -s /usr/bin/ksh tmgrbbtr || true
usermod -aG mqm tmgrbbtr || true

for i in 1 2 3 4 5; do
  useradd -u $((2090 + i)) -g 209 -m -d "/bbtr/traders/t${i}bbtr" -s /usr/bin/ksh "t${i}bbtr" || true
done

useradd -u 180 -g oinstall -G dba -m -s /usr/bin/ksh oracle || true
usermod -aG fuse oracle || true

###############################################################################
# 8) Ownership
###############################################################################
chown -R mqm:mqm /opt/mqm /var/mqm || true
chown -R tmgrbbtr:tmgrbbtr /bbtr || true
chown -R oracle:oinstall /u001 /u002 /u003 /tt_backup /tav62ln12 /tt_dpdump 2>/dev/null || true

###############################################################################
# 9) Java 8
###############################################################################
dnf -y install java-1.8.0-openjdk java-1.8.0-openjdk-devel
JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"

###############################################################################
# 10) Installer staging check (... ) 
###############################################################################
echo "===== Installer staging check: /opt/install ====="
for f in \
  "/opt/install/IBM_MQ_9.2.0.5_LINUX_X86-64.tar.gz" \
  "/opt/install/setup_cobol_server_6.0_redhat_x86_64" \
  "/opt/install/LINUX.X64_193000_db_home.zip"
do
  if [[ -e "$f" ]]; then
    echo "FOUND: $f"
  else
    echo "MISSING: $f"
  fi
done

RUN_INSTALLERS="${RUN_INSTALLERS:-0}"
if [[ "$RUN_INSTALLERS" == "1" ]]; then
  echo "INFO: RUN_INSTALLERS=1 -> attempting optional installs from /opt/install"

  # IBM MQ (optional)
  if rpm -qa | grep -qi '^MQSeries'; then
    echo "INFO: IBM MQ appears installed. Skipping."
  elif [[ -f /opt/install/IBM_MQ_9.2.0.5_LINUX_X86-64.tar.gz ]]; then
    mkdir -p /opt/install/MQ_unpack
    tar -xzf /opt/install/IBM_MQ_9.2.0.5_LINUX_X86-64.tar.gz -C /opt/install/MQ_unpack
    if [[ -x /opt/install/MQ_unpack/MQServer/mqlicense.sh ]]; then
      ( cd /opt/install/MQ_unpack/MQServer && ./mqlicense.sh -accept )
      ( cd /opt/install/MQ_unpack/MQServer && rpm -ivh MQSeries*.rpm || true )
    else
      echo "WARN: MQ unpack did not contain expected MQServer/mqlicense.sh"
    fi
  fi

  # Micro Focus COBOL (optional)
  if [[ -x /opt/install/setup_cobol_server_6.0_redhat_x86_64 ]]; then
    if [[ -d /opt/microfocus/VisualCOBOL6.0/COBOLServer ]]; then
      echo "INFO: MF COBOL target dir exists. Skipping install."
    else
      /opt/install/setup_cobol_server_6.0_redhat_x86_64 \
        -acceptEULA \
        -installLocation="/opt/microfocus/VisualCOBOL6.0/COBOLServer" || true
    fi
  fi
else
  echo "INFO: RUN_INSTALLERS=0 -> not running optional installs."
fi

###############################################################################
# 11) SaltStack hook (optional)
###############################################################################
RUN_SALT="${RUN_SALT:-0}"
SALT_ACTION="${SALT_ACTION:-highstate}"   # examples: highstate OR "state.apply my.state"

if [[ "$RUN_SALT" == "1" ]]; then
  if command -v salt-call >/dev/null 2>&1; then
    echo "INFO: RUN_SALT=1 -> executing: salt-call ${SALT_ACTION}"
    salt-call ${SALT_ACTION} || true
  else
    echo "WARN: RUN_SALT=1 but salt-call not found."
  fi
else
  echo "INFO: RUN_SALT=0 -> skipping salt hook."
fi

###############################################################################
# 12) Final checks (all logged)
###############################################################################
echo "===== FINAL CHECKS ====="
grep '^group:' /etc/nsswitch.conf || true
egrep -v '^\s*#|^\s*$' /etc/security/limits.conf | tail -n 80 || true
pvs || true
vgs || true
lvs || true
df -h || true
egrep 'vg_lnxm12|/u001|/u002|/u003|/bbtr|/tt_backup|/tav62ln12|/tt_dpdump|vg_lnxm12_3-swap' /etc/fstab || true
id oracle || true
id mqm || true
id tmgrbbtr || true
