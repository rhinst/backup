#!/bin/bash

# incremental.sh - A script to perform nightly incremental backups of a
#                  directory structure and MySQL database(s)
#
# @author     Rob Hinst <rob@hinst.net>
# @license    http://opensource.org/licenses/MIT  MIT License
# @link       https://github.com/rhinst/backup

DEBUG=1

#email the results here
EMAIL="yourname@sample.com"
#user to ssh to remote host
BACKUP_USER="username"
#remote host to back up files to
BACKUP_HOST="backuphost.com"
#mysql username
DB_USER="root"
#mysql password
DB_PASS="password"
#mysql host
DB_HOST="localhost"
#directory structure to backup
SRC="/home"
#remote directory to store backups in 
DEST="/backups"
#list of files/directories not to back up
EXCLUDE_LIST="/scripts/backup/excludes.conf"
#list of databases to back up
DB_LIST="/scripts/backup/databases.conf"

#number of daily backups to retain
DAILY_RETENTION=7

function trace {
	if [ $DEBUG == 1 ]; then
		echo $1
	fi	
	echo $1 >> /tmp/backup.log
}


#create empty backup log
rm -f /tmp/backup.log
touch /tmp/backup.log

#make sure the daily backup dir exists
trace "Creating $DEST/daily"
ssh $BACKUP_USER@$BACKUP_HOST mkdir "$DEST/daily" > /dev/null 2>&1

#oldest backup is always the # of total bakcups minus one
let OLDEST=$DAILY_RETENTION-1

#delete the oldest backup set
trace "Removing $DEST/daily/backup.daily.$OLDEST"
ssh $BACKUP_USER@$BACKUP_HOST rm -rf "$DEST/daily/backup.daily.$OLDEST" > /dev/null 2>&1

#move other backups back by 1
let NEXTOLDEST=$OLDEST-1
for i in `seq $NEXTOLDEST -1 0`
do
	let PREV=$i+1
	trace "Moving $DEST/daily/backup.daily.$i to $DEST/daily/backup.daily.$PREV"
	ssh $BACKUP_USER@$BACKUP_HOST mv "$DEST/daily/backup.daily.$i" "$DEST/daily/backup.daily.$PREV" > /dev/null 2>&1
done

#link all files from most recent backup to our new backup dir
trace "Linking $DEST/daily/backup.daily.1 to $DEST/daily/backup.daily.0"
ssh $BACKUP_USER@$BACKUP_HOST cp -al "$DEST/daily/backup.daily.1" "$DEST/daily/backup.daily.0" > /dev/null 2>&1

#rsync the files from .1 to .0
trace "Updating changed files in $DEST/daily/backup.daily.0"
rsync -av --delete --delete-excluded --exclude-from="$EXCLUDE_LIST" "$SRC" $BACKUP_USER@$BACKUP_HOST:$DEST/daily/backup.daily.0
#also back up Adam's heatd source code
rsync -av --delete --delete-excluded "/home/phalcon/heatd.com" $BACKUP_USER@$BACKUP_HOST:$DEST/daily/backup.daily.0

#make sure database directory exists
trace "Creating $DEST/daily/backup.daily.0/databases"
ssh $BACKUP_USER@$BACKUP_HOST mkdir "$DEST/daily/backup.daily.0/databases" > /dev/null 2>&1

#dump databases
for DB_NAME in `cat $DB_LIST`
do
	trace "Dumping database: $DB_NAME"
	mysqldump -u$DB_USER -p$DB_PASS -h$DB_HOST $DB_NAME | ssh $BACKUP_USER@$BACKUP_HOST "dd of=$DEST/daily/backup.daily.0/databases/$DB_NAME.sql"
done

#email the results
cat /tmp/backup.log | /usr/bin/mail -s "Nightly Backup Results" $EMAIL
rm /tmp/backup.log
