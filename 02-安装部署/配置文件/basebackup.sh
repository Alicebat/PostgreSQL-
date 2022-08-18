#!/bin/sh
#You May Yum Install Mailx Fisrt
#And Set pg_hba.conf : host  replication  backup_user  10.63.20.95/32 trust
#Set Configurations Below 
cur_time=`date +%Y-%m-%d-%H-%M-%S`
backup_log=backup-`date +%Y-%m-%d`.log
backup_path=/pgbak/dbbak
archive_path=/pgwal/archive_wals
#DBAMAIL=liuby@vastdata.com.cn,zhoulj@vastdata.com.cn
DBAMAIL=gu.minming@h3c.com,fang_mu@h3c.com,yokel.huang@h3c.com
MONITORMAIL=GW.zhoulijie@h3c.com

#Path 
if [[ ! -d ${backup_path} ]] || [[ ! -d ${archive_path} ]]
then
    echo "`date '+%Y-%m-%d %H:%M:%S '` ERROR: The Backup_path or Archive_path is not exist"
	exit 1
else 
	if [[ ${backup_path} == "/" ]] || [[ ${archive_path} == "/" ]] 
	then
		echo "`date '+%Y-%m-%d %H:%M:%S '` ERROR: Please Check The Backup_path or Archive_path Configuration"
		exit 1
	else 
		touch ${backup_path}/${backup_log}
	fi
fi

#Backup
echo "`date '+%Y-%m-%d %H:%M:%S '` Backup Start" >>${backup_path}/${backup_log}
source /home/postgres/.bashrc
cd ${backup_path}
mkdir ${backup_path}/${cur_time}
pg_basebackup -h  10.63.20.95 -p 5432 -U backup_user -w -D ${backup_path}/${cur_time}  -P  -Ft  -Xs -v -z -l ${cur_time} &>>${backup_path}/${backup_log} 2>&1

#Mail & Clean
if [ $? -eq 0 ]
then
	echo "`date '+%Y-%m-%d %H:%M:%S '` Backup Finished " >>${backup_path}/${backup_log}
	echo "`date '+%Y-%m-%d %H:%M:%S '` Send Mail for Backup Success" >>${backup_path}/${backup_log}
	echo "You may refer to the attached document for details " | mailx -s "PostgreSQL BACKUP FULL DATABASE SUCCESS!! `date '+%Y-%m-%d %H:%M:%S '`" -a ${backup_path}/${backup_log} $DBAMAIL 
	
	#Clean Bak Files
	echo "`date '+%Y-%m-%d %H:%M:%S '` Clean Backup Files of 3 days Ago" >>${backup_path}/${backup_log}
	find ${backup_path} -name '20*' -mtime +2 -exec rm -rf {} \;
	
	#Clean Archive Wals
	echo "`date '+%Y-%m-%d %H:%M:%S '` Clean Archive WALs of 4 days Ago" >>${backup_path}/${backup_log}
	find ${archive_path} -name '0000*' -mtime +3 -exec rm -rf {} \;

else	
	echo "`date '+%Y-%m-%d %H:%M:%S '` ERROR: backup failed " >>${backup_path}/${backup_log}
	echo "`date '+%Y-%m-%d %H:%M:%S '` Send Mail for Backup Failed" >>${backup_path}/${backup_log}
	echo "You may refer to the attached document for details " | mailx -s "PostgreSQL BACKUP FULL DATABASE FAILED!!  `date '+%Y-%m-%d %H:%M:%S '`" -a ${backup_path}/${backup_log} $DBAMAIL 
	echo "You may refer to the attached document for details " | mailx -s "PostgreSQL BACKUP FULL DATABASE FAILED!!  `date '+%Y-%m-%d %H:%M:%S '`" -a ${backup_path}/${backup_log} $MONITORMAIL
	exit 1
fi

