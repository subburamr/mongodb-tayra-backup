#!/usr/bin/expect
log_user 0
set timeout 3
set username [lindex $argv 0];
set password [lindex $argv 1];
set currentdate [lindex $argv 2];
set cmd "/data/backup/tayra/backup.sh -f /data/backup/incremental_backup/backup.log.$currentdate -u $username -t " 
spawn -noecho -ignore HUP {*}$cmd 
expect "Enter password: " { send "$password\r" }
expect eof
