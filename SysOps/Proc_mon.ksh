#!/usr/bin/ksh
# script to detect which process killed my monitored process

monfile=/root/tamsv_monitor.out
logfile=/root/tamsv_proc.out
procN=tamsv

if [ -z `pgrep -n $procN` ] ; then
        echo "Please run the impacted process... Exit"
        exit
fi
nohup strace -p $(pgrep $procN|head -1) -e trace=signal -o $monfile --output-append-mode &

while true
 do
  echo "***********************************************" >> $logfile
  date                                                   >> $logfile
  ps -eH -o pid,ppid,user,start,args                     >> $logfile
  sleep 1
  if [ -z `pgrep -n strace` ] ; then
          break
     fi
 done

Kpid=`cat $monfile |grep -E 'SIGKILL|SIGTERM|SIGSEGV|SIGABRT'|awk -F, '{print $3}'|grep si_pid|sed 's/ si_pid=//'`

for i in `echo $Kpid`
 do
  Kname=`grep $i $logfile`
  echo Process name is $Kname
 done
