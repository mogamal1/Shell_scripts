#!/bin/bash
# CIS SCRIPT
# VERSION 5
WDIR=$1
if [[ `id -u` -ne 0  || -z $1 ]]
then
echo "[ERROR] Please run $0 /<etc> with root account"
exit 10
fi
# ==============================================================================================================
echo ">>> Preparing /etc/fstab file"
echo "Your fstab file is $WDIR/fstab"
FSTAB=$WDIR/fstab
cp $WDIR/fstab /opt/fstab.bkp && echo "Backup of /etc/fstab stored at /opt/fstab.bkp"

if [ `grep -w "/var/tmp" $FSTAB|grep -c defaults,` -eq 0 ]
then
sed -i  '/\/var\/tmp/s/defaults/&,nosuid,nodev,noexec/' $FSTAB
fi
#---------------------------------------------------------------------------------------------------------------
if [ `grep -v "^#" $FSTAB|grep -wc "/tmp"` -eq 0 ]
then
echo "tmpfs   /tmp   tmpfs  defaults,rw,nosuid,nodev,noexec   0 0" >> $FSTAB
elif [ `grep -w "/tmp" $FSTAB|grep -c defaults,` -eq 0 ]
then
sed -i  '/ \/tmp/s/defaults/&,nosuid,noexec,nodev/' $FSTAB
fi
#---------------------------------------------------------------------------------------------------------------
if [ `grep -w "/home" $FSTAB|grep -c defaults,` -eq 0 ]
then
sed -i  '/\/home/s/defaults/&,nodev/' $FSTAB
fi
#---------------------------------------------------------------------------------------------------------------
if [ `grep -v "^#" $FSTAB|grep -wc "/dev/shm"` -eq 0 ]
then
echo "tmpfs   /dev/shm   tmpfs  defaults,rw,nosuid,nodev,noexec  0 0" >> $FSTAB
elif [ `grep -w "/dev/shm" $FSTAB|grep -c nodev` -eq 0 ]
then
sed -i '/\/dev\/shm/s/\(\S\+\s\+\)\(\S\+\s\+\)\(\S\+\s\+\S\+\)\(\s\+\S\+\)/\1\2\3,nosuid,nodev,noexec\4/' $FSTAB
fi
#---------------------------------------------------------------------------------------------------------------
echo "Remounting all paritions. . ."
mount -o remount /dev/shm
mount -o remount /tmp
mount -o remount /home
mount -o remount /var/tmp
mount -a
echo "DONE"
# ==============================================================================================================
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
# ==============================================================================================================
echo ">>> Preparing Banner files"
echo 'All activities performed on this system will be monitored.' > /etc/issue.net
echo 'All activities performed on this system will be monitored.' > /etc/issue
echo 'Removing /etc/motd file'
rm -f /etc/motd
echo "DONE"
# ==============================================================================================================
echo ">>> Preparing sysctl configs"
cat << EOF > /etc/sysctl.d/CIS.conf
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.all.accept_source_route=0
net.ipv6.conf.all.accept_ra=0
net.ipv6.conf.default.accept_ra=0
net.ipv6.conf.default.accept_redirects=0
net.ipv6.conf.default.accept_source_route=0
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
net.ipv4.conf.all.secure_redirects=0
net.ipv4.conf.default.secure_redirects=0
net.ipv4.conf.all.log_martians=1
net.ipv4.conf.default.log_martians=1
net.ipv4.conf.default.rp_filter=1
kernel.randomize_va_space=2
EOF

# 3.2.7 Ensure Reverse Path Filtering is enabled      --------------------------------------------------------------------------------
grep -Els '^s*net.ipv4.conf.all.rp_filters*=s*0' /etc/sysctl.conf /etc/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf /run/sysctl.d/*.conf \
| while read filename; do sed -ri 's/^s*(net.ipv4.net.ipv4.conf.all.rp_filters*)(=)(s*S+b).*$/# *REMOVED* 1/' $filename; done;
sysctl -w net.ipv4.conf.all.rp_filter=1; sysctl -w net.ipv4.route.flush=1
# -------------------------------------------------------------------------------------------------------------------------------------

echo "Applying sysctl configs. . . "
sysctl -w net.ipv6.conf.all.accept_ra=0
sysctl -w net.ipv6.conf.default.accept_ra=0
sysctl -w net.ipv6.conf.all.accept_redirects=0
sysctl -w net.ipv6.conf.default.accept_redirects=0
sysctl -w net.ipv6.conf.all.accept_source_route=0
sysctl -w net.ipv6.conf.default.accept_source_route=0
sysctl -w net.ipv6.route.flush=1
sysctl -w net.ipv4.conf.all.accept_redirects=0
sysctl -w net.ipv4.conf.all.send_redirects=0
sysctl -w net.ipv4.conf.default.accept_redirects=0
sysctl -w net.ipv4.conf.default.send_redirects=0
sysctl -w net.ipv4.conf.default.secure_redirects=0
sysctl -w net.ipv4.conf.all.secure_redirects=0
sysctl -w net.ipv4.conf.all.log_martians=1
sysctl -w net.ipv4.conf.default.log_martians=1
sysctl -w net.ipv4.conf.default.rp_filter=1
sysctl -w net.ipv4.route.flush=1
sysctl -w kernel.randomize_va_space=2
echo "DONE"
# ==============================================================================================================
echo ">>> Preparing AIDE Setup"
(dnf list installed aide || dnf -y install aide) \
&& test -f /var/lib/aide/aide.db.gz \
|| (aide --init && mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz)
echo "AIDE is configured."
chown root:root /etc/systemd/system/aidecheck.*
chmod 0644 /etc/systemd/system/aidecheck.*
systemctl daemon-reload
(systemctl enable aidecheck.service && systemctl --now enable aidecheck.timer ) \
|| echo "0 5 * * * /usr/sbin/aide --check" >> /var/spool/cron/root
echo "AIDE service is scheduled and enabled."
echo "DONE"
# ==============================================================================================================
echo ">>> 1.1.21 Ensure sticky bit is set on all world-writable directories"
#df --local -P|awk '{if (NR!=1) print $6}'|xargs -I '{}' find '{}' \
#-xdev -type d ( -perm -0002 -a ! -perm -1000 ) 2>/dev/null|xargs -I '{}' chmod a+t '{}'
echo "SKIPPED"
# ==============================================================================================================
echo ">>> 4.2.1.3 Ensure rsyslog default file permissions configured"
echo "\$FileCreateMode 0640" >> /etc/rsyslog.conf
echo "DONE"
# ==============================================================================================================
echo ">>> 4.2.2.2 Ensure journald is configured to compress large log files"
grep -e ^[\s]*Compress /etc/systemd/journald.conf|awk '{print} END {if (NR == 0) cmd="echo Compress=yes >> /etc/systemd/journald.conf" ; system(cmd) }'
echo "DONE"
# ==============================================================================================================
echo ">>> 4.2.3 Ensure permissions on all logfiles are configured"
#find /var/log/ -type f -perm /g+wx,o+rwx -exec chmod g-wx,o-rwx '{}' +
echo "SKIPPED"
# ==============================================================================================================
echo ">>> 2.2.1.2 Ensure chrony is configured - user"
grep -qE "^(server|pool)" /etc/chrony.conf || echo "[ERROR] Please configure NTP servers Pool"
grep -qxF "OPTIONS=\"-u chrony\"" /etc/sysconfig/chronyd \
|| ( echo "OPTIONS=\"-u chrony\"" > /etc/sysconfig/chronyd && systemctl restart chronyd )
echo "Chrony service is running with chrony user"
echo "DONE"
# ==============================================================================================================
echo ">>> 5.1.[2,3,4,5,6,7,8] Ensure at/cron is restricted to authorized users"
rm -f /etc/cron.deny
rm -f /etc/at.deny
touch /etc/cron.allow
touch /etc/at.allow
chmod og-rwx /etc/at.allow
chown root:root /etc/at.allow
chmod og-rwx /etc/cron*
chown root:root /etc/cron*
echo "DONE"
