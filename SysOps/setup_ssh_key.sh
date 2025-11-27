#!/bin/bash
#
# Usage: ./setup_ssh_key.sh <remote_user> <remote_host>
# This script performs RSA key setup,
# using SSH multiplexing.
# ## Belal Koura SSNC
## VER 2.1 


if [ "$(id -u)" -eq 0 ]; then
    echo "[ERROR] This script must NOT be run as root."
    exit 1
fi
# --- Arguments ---
if [ $# -ne 2 ]; then
    echo "[INFO] Usage: $0 <remote_user> <remote_host>"
    exit 1
fi

REMOTE_USER="$1"
REMOTE_HOST="$2"
LOCAL_USER="$(id -un)"

SSH_DIR="$HOME/.ssh"
KEY_FILE="$SSH_DIR/id_rsa"
PUB_FILE="$SSH_DIR/id_rsa.pub"
REMOTE_KEY="id_rsa.${LOCAL_USER}.pub"

# ControlMaster socket path
CONTROL_PATH="/tmp/ssh_mux_${LOCAL_USER}_${REMOTE_HOST}"

echo "[INFO] Local user: $LOCAL_USER "
echo "[INFO] Remote target: ${REMOTE_USER}@${REMOTE_HOST} "

echo "[INFO] Checking ~/.ssh "
ls -tr "$SSH_DIR" 2&>/dev/null || mkdir -p "$SSH_DIR"

echo "[INFO] Generating RSA key (if missing) "
if [ ! -f "$KEY_FILE" ] || [ ! -f "$PUB_FILE" ]; then
    /usr/bin/ssh-keygen -t rsa -f "$KEY_FILE" -N ""
fi

echo "[INFO] Creating authorized_keys locally "
cd "$SSH_DIR"
touch authorized_keys
cat id_rsa.pub >> authorized_keys

echo "[INFO] Opening master SSH connection (only one password prompt) "
ssh -o ControlMaster=yes -o ControlPath=$CONTROL_PATH -o ControlPersist=600 \
    ${REMOTE_USER}@${REMOTE_HOST} "echo 'Master SSH session established'"

echo "[INFO] Creating remote ~/.ssh "
ssh -o ControlPath=$CONTROL_PATH ${REMOTE_USER}@${REMOTE_HOST} "mkdir -p ~/.ssh"

echo "[INFO] Using sftp to upload public key "
cd "$SSH_DIR"
sftp -o ControlPath=$CONTROL_PATH ${REMOTE_USER}@${REMOTE_HOST} <<EOF
cd .ssh
put id_rsa.pub ${REMOTE_KEY}
bye
EOF

echo "[INFO] Appending uploaded key to remote authorized_keys "
ssh -o ControlPath=$CONTROL_PATH ${REMOTE_USER}@${REMOTE_HOST} <<EOF
cd ~/.ssh
touch authorized_keys
cat ${REMOTE_KEY} >> authorized_keys
EOF


echo "[INFO] Fixing permissions remotely "
ssh -o ControlPath=$CONTROL_PATH ${REMOTE_USER}@${REMOTE_HOST} "chmod 755 ~/ && chmod -R 700 ~/.ssh"

echo "[INFO] Testing passwordless SSH "
ssh -o ControlPath=$CONTROL_PATH -o PasswordAuthentication=no ${REMOTE_USER}@${REMOTE_HOST} \
    "echo 'Passwordless SSH is working for $LOCAL_USER'"

ssh -O exit -o ControlPath=$CONTROL_PATH ${REMOTE_USER}@${REMOTE_HOST}

echo "[SUCCESS] Key installed at remote: ~/.ssh/${REMOTE_KEY}"
