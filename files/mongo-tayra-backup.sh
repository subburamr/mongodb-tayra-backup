#!/bin/sh
# ------------------------------------------------------------------------------------------------------------------------------------
# Title			: MongoDB Backup
# Description		: This script performs MongoDB full backup using mongodump and Incremental backup using the Tayra tool
# VERSION		: 1.0
# Author		: Subburam Rajaram
# Date			: 16.11.2015
# ------------------------------------------------------------------------------------------------------------------------------------

# Backup Directory Structure
# /data/backup
# ├── archive            				- Old backups
# ├── dump						- Current full backup taken with mongodump
# ├── incremental_backup				- Current Incremental backup with Tayra
# └── tayra  						- Tayra program
#     ├── backup.sh					- Tayra	Incremental Backup script
#     ├── restore.sh					- Tayra Restore Script
#     └── timestamp.out					- Tayra stores oplog after the indicated timestamp present in this file.



FULLBACKUP_FREQUENCY=14  # Default no. of days, can be overridden with command line parameter -d
FULL_BACKUP=true
FULLBACKUP_DIR=/data/backup/dump
LATEST_FULLBACKUP=/data/backup/archive/backup_latest.tar.gz
TAYRA_DIR=/data/backup/tayra
CURRENT_DATE=`date +%F`

usage () {
  echo ""
  echo "USAGE: "
  echo "  $0"
  echo "  $0 [-d 14]"
  echo "    -d number of days between full backup ; Default - 14"
  echo ""
  exit 1
}

while getopts "d:" opt; do
  case $opt in
    d)
      if ! echo $OPTARG | grep -q "[A-Za-z]" && [ -n "$OPTARG" ]
      then
        FULLBACKUP_FREQUENCY=$OPTARG
      else
        usage
      fi
    ;;
    *)
      usage
    ;;
  esac
done


# Cleanup old backup processes
OLD_BACKUP_PROCS=$(ps aux | grep '/data/backup'|grep -v grep|awk '{print $2}')
if [ -n "$OLD_BACKUP_PROCS" ]; then
	echo "Terminating old backup processes"
	kill -1 $OLD_BACKUP_PROCS
fi


# Archive backup and clean up tasks
fullbackup_archive() {
	echo "Archiving previous backup"
	tar -P --numeric-owner --preserve-permissions -czf /data/backup/archive/backup_$CURRENT_DATE.tar.gz /data/backup/dump /data/backup/incremental_backup/
	rm -f /data/backup/archive/backup_latest.tar.gz
	rm -rf /data/backup/dump/* /data/backup/incremental_backup/*
	ln -s /data/backup/archive/backup_$CURRENT_DATE.tar.gz /data/backup/archive/backup_latest.tar.gz
}


# Backup Function
runbackup() {

	#run the full backup 
	if [ "$FULL_BACKUP" = true ] ; then
		# Archive previous backup files
		fullbackup_archive
		
		# Get latest timestamp
		echo "Executing a FULL backup"
		LATEST_DB_TIMESTAMP=`mongo local --eval 'db.oplog.rs.find({}, {ts:1}).sort({$natural:-1}).limit(1).forEach(printjson)'|tail -1| awk -F'[(,]' '{print $2}'`
		echo $LATEST_DB_TIMESTAMP
		EXITSTATUS1=`echo $?`

		# Write LATEST_TIMESTAMP to timestamp.out file under /data/backup/tayra
		echo "{ \"ts\" : { \"\$ts\" : $LATEST_DB_TIMESTAMP , \"\$inc\" : 1} }" | tee /data/backup/tayra/timestamp.out 1> /dev/null

		# Trigger mongodump to write to /data/backup/dump
		mongodump -o $FULLBACKUP_DIR
		EXITSTATUS2=`echo $?`
	fi

	# Tayra backup run under $TAYRA_DIR so that the timestamp.out is picked up by the processes
	cd $TAYRA_DIR 
	/data/backup/tayra/backup.sh -f /data/backup/incremental_backup/backup.log.$CURRENT_DATE -t 1> /dev/null & 
}


if [ -f "$LATEST_FULLBACKUP" ]; then
	LAST_FULL_BACKUP_DATE=`ls -ld --time-style="+%F" $LATEST_FULLBACKUP|awk '{print $6}'`
	DATE_DIFFERENCE=$(echo "((`date -d "$CURRENT_DATE" +%s`) - (`date -d "$LAST_FULL_BACKUP_DATE" +%s`))/86400"|bc -l|cut -d "." -f1)
	echo "Last Full backup was taken $DATE_DIFFERENCE days ago"

	if [ "$DATE_DIFFERENCE" -lt "$FULLBACKUP_FREQUENCY" ]; then
		# full backup is not required
		FULL_BACKUP=false 
		echo "Full backup not required"
	fi	
fi


# Check if the host is master 
IS_MASTER=`mongo --quiet --eval "d=db.isMaster(); print( d['ismaster'] );"` #
if [ "$IS_MASTER" = true ] ; then
	# Try stepping down
	##  	mongo --quiet --eval "rs.stepDown();"
	echo "Could not proceed with the backup as I am the Primary node"
else 
	# I am a secondary node, safe to proceed with the backup 
	runbackup
fi


# Unset variables initialized
echo "Unsetting variables"
for VARIABLES in FULLBACKUP_FREQUENCY FULL_BACKUP FULLBACKUP_DIR LATEST_FULLBACKUP TAYRA_DIR CURRENT_DATE LAST_FULL_BACKUP_DATE DATE_DIFFERENCE OLD_BACKUP_PROCS LATEST_DB_TIMESTAMP IS_MASTER
do
	unset $VARIABLES
done
