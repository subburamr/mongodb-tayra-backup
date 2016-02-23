#!/bin/sh
# ------------------------------------------------------------------------------------------------------------------------------------
# Title			: MongoDB Backup
# Description		: This script performs MongoDB full backup using mongodump and Incremental backup using the Tayra tool
# VERSION		: 1.2
# Author		: Subburam Rajaram
# Date			: 21.2.2016
# ------------------------------------------------------------------------------------------------------------------------------------

FULLBACKUP_FREQUENCY=14  		# Default no. of days for full backup, can be overridden with command line parameter -d
FULL_BACKUP=true
FULLBACKUP_DIR=/data/backup/mongodb/full
LATEST_ARCHIVE=/data/backup/mongodb/archive/archive_latest.tar.gz
TAYRA_DIR=/opt/tayra
CURRENT_DATE=`date +%F`
OPT="" 							# OPT string for use with Tayra
AUTHOPT=""						# AUTHOPT string for use with mongodump
SECURE=false					
PROGNAME=$(basename $0)
LOGSTAMP="$(date) $(hostname) ${PROGNAME}"

echo "$LOGSTAMP: Initiating the script"
usage () {
  echo ""
  echo "USAGE: "
  echo "  $0"
  echo "  $0 [-d 14]"
  echo "  $0 [-d 14 -u <username> -p <password>]"
  echo ""
  echo "Options"
  echo "    -d number of days between full backup ; Default - 14"
  echo "    -u username"
  echo "    -p password"
  echo ""
  exit 1
}

trap error_exit "Kill signal recevied! Aborting" HUP INT TERM

# Exit on Error
error_exit() {
	# Display error message and exit
	echo "$LOGSTAMP: ERROR ${1:-"Unknown Error"}" 1>&2
	clean_up 1
}

# Clean up function 
clean_up() {
	if [ $# -eq 0 ]
  		then
  			echo "$LOGSTAMP: Script has completed successfully"
	fi
	for VARIABLES in FULLBACKUP_FREQUENCY FULL_BACKUP FULLBACKUP_DIR LATEST_ARCHIVE TAYRA_DIR CURRENT_DATE LATEST_ARCHIVE_DATE DATE_DIFFERENCE OLD_BACKUP_PROCS LATEST_DB_TIMESTAMP IS_MASTER LOGSTAMP
	do
		unset $VARIABLES
	done
	exit $1
}

while getopts "d:u:p:" opt; do
  case $opt in
    d)
      if ! echo $OPTARG | grep -q "[A-Za-z]" && [ -n "$OPTARG" ]
      then
        FULLBACKUP_FREQUENCY=$OPTARG
      else
        usage
      fi
    ;;
    u) BACKUP_USERNAME=${OPTARG} ;;
    p) BACKUP_PASSWORD=${OPTARG} ;;
    *)
      usage
    ;;
  esac
done


# kill old backup processes
OLD_BACKUP_PROCS=$(ps aux | grep '/data/backup/mongodb'|grep -v grep|awk '{print $2}')
if [ -n "$OLD_BACKUP_PROCS" ]; then
	echo "$LOGSTAMP: Terminating old backup processes"
	kill -15 $OLD_BACKUP_PROCS || error_exit "The previous backup processes could not be killed! Aborting"						
fi

# Do we need username/password to access database
if [ -n "$BACKUP_USERNAME" ] && [ -n "$BACKUP_PASSWORD" ]; then
  OPT="$OPT -u $BACKUP_USERNAME -p $BACKUP_PASSWORD"
  AUTHOPT="$OPT --authenticationDatabase admin"
  SECURE=true
fi

# Archive backup and clean up tasks
archive_prev_backup() {
	echo "$LOGSTAMP: Archiving previous backup"
	tar -P --numeric-owner --preserve-permissions -czf /data/backup/mongodb/archive/archive_$CURRENT_DATE.tar.gz /data/backup/mongodb/full /data/backup/mongodb/incremental || error_exit " Unable to archive previous backup! Aborting"
	rm -f /data/backup/mongodb/archive/archive_latest.tar.gz
	rm -rf /data/backup/mongodb/full/* /data/backup/mongodb/incremental/*
	ln -s /data/backup/mongodb/archive/archive_$CURRENT_DATE.tar.gz /data/backup/mongodb/archive/archive_latest.tar.gz
}

# Backup Function
runbackup() {

	#run the full backup 
	if [ "$FULL_BACKUP" = true ] ; then
		# Archive previous backup files
		if [ $(ls /data/backup/mongodb/full | wc -l) -ne 0 ]; then
			archive_prev_backup
		fi
		echo "$LOGSTAMP: Executing a FULL backup"
		LATEST_DB_TIMESTAMP=`mongo local $AUTHOPT --eval 'db.oplog.rs.find({}, {ts:1}).sort({$natural:-1}).limit(1).forEach(printjson)'|tail -1| awk -F'[(,]' '{print $2}'`
		echo $LATEST_DB_TIMESTAMP

		# Write LATEST_TIMESTAMP to /opt/tayra/timestamp.out
		echo -n "{ \"ts\" : { \"\$ts\" : $LATEST_DB_TIMESTAMP , \"\$inc\" : 1} }" | tee /opt/tayra/timestamp.out 1> /dev/null || error_exit "Unable to update timestamp.out file! Aborting"

		# Trigger mongodump to write full backup
		mongodump $AUTHOPT -o $FULLBACKUP_DIR || error_exit "Unable to take backup using mongodump! Aborting"
	fi

	cd $TAYRA_DIR || error_exit "Cannot change directory! Aborting"
	if [ "$SECURE" = true ] ; then
		/opt/tayra/backup_expect.sh $BACKUP_USERNAME $BACKUP_PASSWORD $CURRENT_DATE 1> /dev/null &
	else
		/opt/tayra/backup.sh -f /data/backup/mongodb/incremental/backup.log.$CURRENT_DATE -t 1> /dev/null &
	fi 
}

if [ -f "$LATEST_ARCHIVE" ]; then
	LATEST_ARCHIVE_DATE=`ls -ld --time-style="+%F" $LATEST_ARCHIVE|awk '{print $6}'`
	DATE_DIFFERENCE=$(echo "((`date -d "$CURRENT_DATE" +%s`) - (`date -d "$LATEST_ARCHIVE_DATE" +%s`))/86400"|bc -l|cut -d "." -f1)
	echo "$LOGSTAMP: Last Archive was taken $DATE_DIFFERENCE days ago"

	if [ "$DATE_DIFFERENCE" -lt "$FULLBACKUP_FREQUENCY" ]; then
		FULL_BACKUP=false 
		echo "$LOGSTAMP: Full backup not required"
	fi	
fi

# Check if the host is master 
IS_MASTER=`mongo --quiet --eval "d=db.isMaster(); print( d['ismaster'] );"`
if [ "$IS_MASTER" = true ] ; then
	error_exit "Unable to take backup as I am the Primary node! Aborting"
else 
	# I am a secondary node, safe to proceed with the backup 
	runbackup
fi

clean_up