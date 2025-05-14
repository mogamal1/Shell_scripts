#!/bin/ksh
## Rollback/cleanup script for MQM and ports  

if [[ -z "$1" ||  $EUID -ne 0 ]]; then
   echo "[Error] Usage ./$0 <pattern>"
   exit 1
fi

####### MQM Part ########
echo "[Info] Stopping $1 MQ ..."
MQ_NAME=`echo $1 | tr '[:lower:]' '[:upper:]'`
su - mqm -c "endmqm $MQ_NAME" && echo "Please waith for stopping $MQ_NAME" && sleep 60 
su - mqm -c "dltmqm $MQ_NAME"

###  User/Group Part ####
echo "[Info] removing $1 users and groups..."
cpdate /etc/passwd
cpdate /etc/group
grep  "^.*$1:x" /etc/passwd | awk -F: '{print $1}'|xargs -I {} userdel {}
grep  "^.*$1:x" /etc/group  | awk -F: '{print $1}'|xargs -I {} groupdel {}

##### services part #####
echo "[Info] removing $1 ports..."
cpdate /etc/services
sed -i '/^.*$1.*tcp/d' /etc/services

#### Filesystem Part ####
echo "[Info] removing $1 dirs content..."
rm -r /*$1/* 
