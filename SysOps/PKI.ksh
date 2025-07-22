#!/usr/bin/ksh
### PKI Setup
### Belal Koura SSNC
### Version 1.2

# -------------
# Usage Check
# -------------
if [ -z "$1" ]; then
    echo "Usage: $0 <remote_host>"
    echo "INFO: Oracle user used by default"
    exit 1
fi

# -------------
# Configuration
# -------------
REMOTE_USER="oracle"
REMOTE_HOST="$1"  # Passed as argument

# -------------------
# Detect OS and Paths
# -------------------
OS_NAME=$(uname -s)
case "$OS_NAME" in
    SunOS|Linux)  SSH_KEYGEN="/usr/bin/ssh-keygen" ;;
    *) echo "ERROR: Unsupported OS: $OS_NAME" >&2; exit 1 ;;
esac

# ------------------
# Initialize Logging
# ------------------
echo "=== Starting Non-Interactive SSH Setup ==="
echo "Date: $(date)"
echo "User: $(whoami)"
echo "Host: $(hostname)"
echo "OS: $OS_NAME"
echo "Remote Host: $REMOTE_HOST"

# -------------
# Validate User
# -------------
[ "$(whoami)" = "root" ] && { echo "ERROR: Do not run as root." >&2; exit 1; }

# ----------------
# Local Key Setup
# ----------------
mkdir -p ~/.ssh 2>/dev/null && chmod 700 ~/.ssh || { echo "ERROR: Failed to create ~/.ssh"; exit 1; }
cd ~/.ssh || exit 1

if [ ! -f id_rsa ] || [ ! -f id_rsa.pub ]; then
    echo "Generating new SSH keys..."
    $SSH_KEYGEN -t rsa -b 2048 -N "" -f id_rsa -q || { echo "ERROR: Keygen failed"; exit 1; }
fi

touch authorized_keys
chmod 600 authorized_keys
grep -q "$(cat id_rsa.pub)" authorized_keys 2>/dev/null || cat id_rsa.pub >> authorized_keys

# ----------------
# Remote Deployment
# ----------------
echo "Deploying key to $REMOTE_USER@$REMOTE_HOST..."
LOCAL_USER=$(whoami)
REMOTE_KEY_FILE="id_rsa.${LOCAL_USER}.pub"

ssh-keyscan -H "$REMOTE_HOST" >> ~/.ssh/known_hosts 2>/dev/null

sftp -oBatchMode=no -b - "$REMOTE_USER@$REMOTE_HOST" <<EOF >/dev/null 2>&1
cd .ssh || mkdir -p .ssh && chmod 700 .ssh
put id_rsa.pub $REMOTE_KEY_FILE
bye
EOF

ssh -oBatchMode=no "$REMOTE_USER@$REMOTE_HOST" <<EOF >/dev/null 2>&1
mkdir -p ~/.ssh
chmod 700 ~/.ssh
cd ~/.ssh
touch authorized_keys
chmod 600 authorized_keys
grep -q "\$(cat $REMOTE_KEY_FILE)" authorized_keys || cat $REMOTE_KEY_FILE >> authorized_keys
chmod 755 ~
EOF

# ------------------
# Verify Connection
# ------------------
echo "Verifying passwordless access..."
ssh -o BatchMode=yes -o ConnectTimeout=5 "$REMOTE_USER@$REMOTE_HOST" "echo SUCCESS" || {
    echo "ERROR: Passwordless login failed. Check:"
    echo "1. Remote ~/.ssh/authorized_keys permissions (must be 600)"
    echo "2. SSH debug: ssh -v $REMOTE_USER@$REMOTE_HOST"
    exit 1
}

echo "=== Setup completed! ==="
