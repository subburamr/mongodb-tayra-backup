Puppet implementation of mongodb-tayra-backup

This puppet module creates appropriate directory structure  under /data/backup and places the required scripts to take full backup using mongodump and incremental backup using tayra

Add the below entry to crontab so that its run everyday
	0 6 * * * root /usr/local/bin/mongo-tayra-backup.sh  > /dev/null

How the backup script works?

	- The timestamp of the last oplog entry is recorded via below command and written to /data/backup/tayra/timestamp.out
	mongo local --eval 'db.oplog.rs.find({}, {ts:1}).sort({$natural:-1}).limit(1).forEach(printjson)'|tail -1| awk -F'[(,]' '{print $2}'

	- If there are no previous full backup or if the last full backup is older than 14 days(threshold can be modified via commandline parameter -d)
		then FULL Backup is performed using mongodump

	- Incremental Backup - start Tayra in tailable format and it would record data based on the timestamp mentioned in the /data/backup/tayra/timestamp.out file


Secure Databases:

	- For secure databases, the script would need to be passed username and password parameters. 

	Crontab entry:
	/usr/local/bin/mongo-tayra-backup.sh  -u <usernamewithbackuprole> -p <password> > /dev/null

	- For secure databases, the tayra script is spawned from expect 
	This ensures that the password is not displayed as a command line parameter on running "ps"

