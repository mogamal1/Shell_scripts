#!/bin/bash
WDIR=$1
if [ `id -u` -ne 0 ]
then
echo "[ERROR] Please run $0 $1 with root account"
exit 10
fi

echo ">>> Preparing /etc/fstab file"
echo "Your fstab file is $WDIR/fstab"
FSTAB=$WDIR/fstab
cp $WDIR/fstab /tmp/fstab.bkp && echo "Backup of /etc/fstab stored at /tmp/fstab.bkp"

if [ `grep -w "/var/tmp" $FSTAB|grep -c defaults,` -eq 0 ]
then
sed -i  '/\/var\/tmp/s/defaults/&,nosuid,nodev,noexec/' $FSTAB
fi

if [ `grep -w "/tmp" $FSTAB|grep -c defaults,` -eq 0 ]
then
sed -i  '/ \/tmp/s/defaults/&,nosuid,noexec/' $FSTAB
fi

if [ `grep -w "/home" $FSTAB|grep -c defaults,` -eq 0 ]
then
sed -i  '/\/home/s/defaults/&,nodev/' $FSTAB
fi

if [ `grep -w "/dev/shm" $FSTAB|grep -c defaults,` -eq 0 ]
then
sed -i  '/\/dev\/shm/s/defaults/&,nosuid,nodev,noexec/' $FSTAB
fi
echo "Remounting all paritions. . ."
mount -a
echo "DONE"
# ===========================================================================================
echo ">>> Preparing /etc/modprobe.d/CIS.conf file"
cat << EOF > /etc/modprobe.d/CIS.conf
install cramfs /bin/true
install freevxfs /bin/true
install jffs2 /bin/true
install hfs /bin/true
install hfsplus /bin/true
install squashfs /bin/true
install udf /bin/true
install vfat /bin/true
EOF

cat << EOF > /etc/modprobe.d/dccp.conf
install dccp /bin/true
EOF

echo "DONE"
# ===========================================================================================
echo ">>> Preparing Banner files"
echo 'Authorized uses only. All activity may be monitored and reported.' > /etc/issue.net
echo 'Authorized uses only. All activity may be monitored and reported.' > /etc/issue
echo "DONE"
# ===========================================================================================
echo ">>> Preparing sysctl configs"
cat << EOF > /etc/sysctl.d/CIS.conf
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.all.accept_source_route=0
net.ipv6.conf.all.accept_ra=0
net.ipv6.conf.default.accept_ra=0
net.ipv6.conf.default.accept_redirects=0
net.ipv6.conf.default.accept_source_route=0
EOF
echo "Applying sysctl configs. . . "
sysctl -w net.ipv6.conf.all.accept_ra=0
sysctl -w net.ipv6.conf.default.accept_ra=0
sysctl -w net.ipv6.route.flush=1
sysctl -w net.ipv6.conf.all.accept_redirects=0
sysctl -w net.ipv6.conf.default.accept_redirects=0
sysctl -w net.ipv6.route.flush=1
sysctl -w net.ipv4.conf.all.accept_redirects=0
sysctl -w net.ipv4.conf.default.accept_redirects=0
sysctl -w net.ipv4.route.flush=1
echo "DONE"
# ===========================================================================================
echo ">>> Preparing AIDE Setup"
(dnf list installed aide || dnf -y install aide) && test -f /var/lib/aide/aide.db.gz || (aide --init && mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz)
echo "AIDE is configured."
chown root:root /etc/systemd/system/aidecheck.*
chmod 0644 /etc/systemd/system/aidecheck.*
systemctl daemon-reload
systemctl enable aidecheck.service
systemctl --now enable aidecheck.timer
echo "AIDE service is scheduled and enabled."
echo "DONE"
# ===========================================================================================
echo ">>> 1.1.21 Ensure sticky bit is set on all world-writable directories"
#df --local -P|awk '{if (NR!=1) print $6}'|xargs -I '{}' find '{}' \
#-xdev -type d ( -perm -0002 -a ! -perm -1000 ) 2>/dev/null|xargs -I '{}' chmod a+t '{}'
echo "SKIPPED"
# ===========================================================================================
echo ">>> 4.2.3 Ensure permissions on all logfiles are configured"
#find /var/log/ -type f -perm /g+wx,o+rwx -exec chmod g-wx,o-rwx '{}' +
echo "SKIPPED"
# ===========================================================================================
echo ">>> 2.2.1.2 Ensure chrony is configured - user"
echo "Add or edit server or pool lines to /etc/chrony.conf as appropriate:
server <remote-server>
Configure chrony to run as the chrony user /etc/chrony/chrony.conf"
echo "DONE"
# ===========================================================================================
echo ">>> 5.1.8 Ensure at/cron is restricted to authorized users"
rm -f /etc/cron.deny
rm -f /etc/at.deny
touch /etc/cron.allow
touch /etc/at.allow
chmod og-rwx /etc/cron.allow
chmod og-rwx /etc/at.allow
chown root:root /etc/cron.allow
chown root:root /etc/at.allow
echo "DONE"
