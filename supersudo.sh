#!/bin/bash
# This script run sudo commands on remote hosts with password authentication 
# password is in cleartext format
# CopyRight by MohamedGamal (github.com/mogamal1)
echo "This Script works only in **LINUX** MACHINES"
if [ -z $1 ] 
then 
echo "Please run with argument $0 servers_list_file" ; exit 
fi	

for i in `cat $1`
do
echo "### $i ###"
ssh "$i" 'echo PASSWORD_HERE_PLEASE |sudo -S sh -c "sed -i '"'"'/^AllowUser/ s/$/ aabdel/'"'"' /etc/ssh/sshd_config;grep -c aabdel /etc/ssh/sshd_config;service sshd restart;usermod -aG wheel aabdel;id aabdel"'
echo "### Done ###"
done
