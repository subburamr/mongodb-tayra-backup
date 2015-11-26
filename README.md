# mongodb-tayra-backup
puppet implementation of mongodb-tayra-backup

How it works?

    Based on last full backup archive, full backup is done using mongodump otherwise incremental backup is executed with Tayra

    FULL backup - Get timestamp of the last oplog entry from mongodump via below command
    mongo local --eval 'db.oplog.rs.find({}, {ts:1}).sort({$natural:-1}).limit(1).forEach(printjson)'|tail -1| awk -F'[(,]' '{print $2}'
    and take full backup with mongodump command under /data/backup/dump

    Incremental Backup - start Tayra in tailable format and it would record data based on the timestamp mentioned in the /data/backup/tayra/timestamp.out file
