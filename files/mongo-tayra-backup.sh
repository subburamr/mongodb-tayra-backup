#!/bin/sh
# ------------------------------------------------------------------------------------------------------------------------------------
# Title			: MongoDB Backup
# Description		: This script performs MongoDB full backup using mongodump and Incremental backup using the Tayra tool
# VERSION		: 1.1
# Author		: Subburam Rajaram
# Date			: 15.1.2016
# ------------------------------------------------------------------------------------------------------------------------------------

# Backup Directory Structure
# /data/backup/mongodb
# ├── archive            				- Archived backups
# ├── full						- Latest full backup taken with mongodump
# ├── incremental				- Latest Incremental backup with Tayra
# 
#
# /opt/tayra  						- Tayra program
#     ├── backup.sh					- Tayra	Incremental Backup script
#     ├── restore.sh					- Tayra Restore Script
#     └── timestamp.out					- Tayra stores oplog after the indicated timestamp present in this file.



# On exit of tayra process it should update timestamp.out, so it should not be sent (kill -9)SIGKILL.
# Modification, the tayra script is to be spawned via expect and the spawned process ignores HUP signal. So it should be terminated with kill -15(SIGTERM)


FULLBACKUP_FREQUENCY=14  		# Default no. of days, can be overridden with command line parameter -d
FULL_BACKUP=true
FULLBACKUP_DIR=/data/backup/mongodb/full
LATEST_ARCHIVE=/data/backup/mongodb/archive/archive_latest.tar.gz
TAYRA_DIR=/opt/tayra
CURRENT_DATE=`date +%F`
OPT="" 							# OPT string for use with Tayra
AUTHOPT=""						# AUTHOPT string for use with mongodump
SECURE=false					# Boolean to check if the DB requires authentication
PROGNAME=$(basename $0)

echo "$(date -u) $(hostname) ${PROGNAME}:Initiating mongodb-tayra script"
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

# Exit on Error
error_exit() {
	# Display error message and exit
	echo "$(date -u) $(hostname) ${PROGNAME}: ERROR ${1:-"Unknown Error"}" 1>&2
	clean_up 1
}

# Clean up function 
clean_up() {
	# Perform program exit housekeeping
	# Optionally accepts an exit status
	# Unset variables initialized
	# echo "Unsetting variables"
	for VARIABLES in FULLBACKUP_FREQUENCY FULL_BACKUP FULLBACKUP_DIR LATEST_ARCHIVE TAYRA_DIR CURRENT_DATE LATEST_ARCHIVE_DATE DATE_DIFFERENCE OLD_BACKUP_PROCS LATEST_DB_TIMESTAMP IS_MASTER
	do
		unset $VARIABLES
	done

	if [ $# -eq 0 ]
  		then
  			echo "$(date -u) $(hostname) ${PROGNAME}: mongodb-tayra script has completed successfully"
	fi
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


# Cleanup old backup processes
OLD_BACKUP_PROCS=$(ps aux | grep '/data/backup/mongodb'|grep -v grep|awk '{print $2}')
if [ -n "$OLD_BACKUP_PROCS" ]; then
	echo "$(date -u) $(hostname) ${PROGNAME}: Terminating old backup processes"
	kill -15 $OLD_BACKUP_PROCS || error_exit "$LINENO: The previous backup processes could not be killed! Aborting"						
fi

# Do we need username/password to access database
if [ -n "$BACKUP_USERNAME" ] && [ -n "$BACKUP_PASSWORD" ]; then
  OPT="$OPT -u $BACKUP_USERNAME -p $BACKUP_PASSWORD"
  AUTHOPT="$OPT --authenticationDatabase admin"
  SECURE=true
fi

# Archive backup and clean up tasks
archive_prev_backup() {
	echo "$(date -u) $(hostname) ${PROGNAME}: Archiving previous backup"
	tar -P --numeric-owner --preserve-permissions -czf /data/backup/mongodb/archive/archive_$CURRENT_DATE.tar.gz /data/backup/mongodb/full /data/backup/mongodb/incremental || error_exit "$LINENO: Unable to archive previous backup! Aborting"
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
		# Get latest timestamp
		echo "$(date -u) $(hostname) ${PROGNAME}: Executing a FULL backup"
		LATEST_DB_TIMESTAMP=`mongo local $AUTHOPT --eval 'db.oplog.rs.find({}, {ts:1}).sort({$natural:-1}).limit(1).forEach(printjson)'|tail -1| awk -F'[(,]' '{print $2}'`
		echo $LATEST_DB_TIMESTAMP
		#EXITSTATUS1=`echo $?`

		# Write LATEST_TIMESTAMP to timestamp.out file under /opt/tayra
		echo -n "{ \"ts\" : { \"\$ts\" : $LATEST_DB_TIMESTAMP , \"\$inc\" : 1} }" | tee /opt/tayra/timestamp.out 1> /dev/null || error_exit "$LINENO: Unable to update timestamp.out file! Aborting"

		# Trigger mongodump to write full backup to /data/backup/mongodb/full
		mongodump $AUTHOPT -o $FULLBACKUP_DIR || error_exit "$LINENO: Unable to take backup using mongodump"
		#EXITSTATUS2=`echo $?`
	fi

	# Tayra backup run under $TAYRA_DIR as working directory so that the timestamp.out is picked up by the processes
	cd $TAYRA_DIR || error_exit "$LINENO: Cannot change directory! Aborting"
	if [ "$SECURE" = true ] ; then
		/opt/tayra/backup_expect.sh $BACKUP_USERNAME $BACKUP_PASSWORD $CURRENT_DATE 1> /dev/null &
	else
		/opt/tayra/backup.sh -f /data/backup/mongodb/incremental/backup.log.$CURRENT_DATE -t 1> /dev/null &
	fi 
}


trap clean_up HUP INT TERM

if [ -f "$LATEST_ARCHIVE" ]; then
	LATEST_ARCHIVE_DATE=`ls -ld --time-style="+%F" $LATEST_ARCHIVE|awk '{print $6}'`
	DATE_DIFFERENCE=$(echo "((`date -d "$CURRENT_DATE" +%s`) - (`date -d "$LATEST_ARCHIVE_DATE" +%s`))/86400"|bc -l|cut -d "." -f1)
	echo "$(date -u) $(hostname) ${PROGNAME}: Last Archive was taken $DATE_DIFFERENCE days ago"

	if [ "$DATE_DIFFERENCE" -lt "$FULLBACKUP_FREQUENCY" ]; then
		# full backup is not required
		FULL_BACKUP=false 
		echo "$(date -u) $(hostname) ${PROGNAME}: Full backup not required"
	fi	
fi


# Check if the host is master 
IS_MASTER=`mongo --quiet --eval "d=db.isMaster(); print( d['ismaster'] );"` #
if [ "$IS_MASTER" = true ] ; then
	# Try stepping down
	##  	mongo --quiet --eval "rs.stepDown();"
	echo "$(date -u) $(hostname) ${PROGNAME}: Could not proceed with the backup as I am the Primary node" && error_exit "$LINENO: Unable to take backup using mongodump. Aborting"
else 
	# I am a secondary node, safe to proceed with the backup 
	runbackup
fi

clean_up
