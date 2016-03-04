#!/bin/bash
#
# Restore backups made with Percona XtraBackup tool
# Daniel Guzman Burgos <daniel.guzman.burgos@percona.com>
#

clear

set -o pipefail

# Initial values

lockFile="/var/lock/xtrabackup.lock"
errorFile="/var/log/mysql/xtrabackup.err"
logFile="/var/log/mysql/xtrabackup.log"
mysqlUser=root
mysqlPort=3306
backupPath="${backupPath-"/root/backups/"}"
restorePath="/var/lib/datadir"
email="daniel.guzman.burgos@percona.com"

# Function definitions

function sendAlert () {
        if [ -e "$errorFile" ]
        then
                alertMsg=$(cat $errorFile)
                echo -e "${alertMsg}" | mailx -s "[$HOSTNAME] ALERT XtraBackup backup" "${email}"
        fi
}

function destructor () {
        sendAlert
        rm -f "$lockFile" "$errorFile"
}

# Setting TRAP in order to capture SIG and cleanup things
trap destructor EXIT INT TERM

function logInfo (){
        echo "[$(date +%y%m%d-%H:%M:%S)] $1" >> $logFile
}

function verifyExecution () {
        local exitCode="$1"
        local mustDie=${3-:"false"}
        if [ $exitCode -ne "0" ]
        then
                msg="[ERROR] Failed execution. ${2}"
                echo "$msg" >> ${errorFile}
                logInfo "${msg}"
                if [ "$mustDie" == "true" ]; then
                        exit 1
                else
                        return 1
                fi
        fi
        return 0
}

function setLockFile () {
        if [ -e "$lockFile" ]; then
                trap - EXIT INT TERM
                verifyExecution "1" "Script already running. $lockFile exists"
                sendAlert
                rm -f "$errorFile"
                exit 2
        else
                touch "$lockFile"
        fi
}

function verifyXtrabackup () {
	which xtrabackup &> /dev/null
        verifyExecution "$?" "Cannot find xtrabackup tool" true
        logInfo "[OK] Found 'xtrabackup' bin"

	which innobackupex &> /dev/null
	verifyExecution "$?" "Cannot find innobackupex tool" true
        logInfo "[OK] Found 'innobackupex' bin"
}

function verifyMysqlBin () {
	which mysql &> /dev/null
        verifyExecution "$?" "Cannot find mysql bin" true
        logInfo "[OK] Found 'mysql' bin"
}

function verifyQpress () {
	which qpress &> /dev/null
        verifyExecution "$?" "Cannot find qpress tool" true
        logInfo "[OK] Found 'qpress' bin"
}

function verifySpace () {

	isCompress=0
	isCompact=0

	spaceOnDisk=$(df -P ${restorePath} | tail -1 | awk '{print $4*1024}')
	verifyExecution "$?" "Cannot find space available on disk $restorePath" true
	backupSize=$(du -sb $backupPath | awk '{print $1}')
	verifyExecution "$?" "Cannot find backup size for $backupPath" true
	type=$(file -bi $backupPath/xtrabackup_info* | head -n1)
	verifyExecution "$?" "Cannot find file $backupPath/xtrabackup_info. No way to find if is compressed or not. Space available might not be enough. Run at your own risk!"
	if [[ $type != *"text"* ]]; then
		verifyQpress
		logInfo "Compressed backup"
		backupSize=$(($backupSize*43))
		isCompress=1
	fi
	out=$(cat $backupPath/xtrabackup_checkpoints | grep full-backuped)
	verifyExecution "$?" "Backup is not full backup." true
	out=$(cat $backupPath/xtrabackup_checkpoints | grep compact | grep 1)
	if [ $? -eq 0 ]; then
		logInfo "Compact backup"
		backupSize=$( printf "%.0f" $(echo $backupSize*1.02 | bc))
		isCompact=1
	else
		logInfo "Regular full backup (not compressed, not compact)"
	fi

	percent=$(printf "%.0f" $(echo $spaceOnDisk*0.9 | bc))
	if [ $backupSize -gt $percent ]; then
		verifyExecution "1" "Not enough space in disk for restore." true
	fi
	logInfo "Space available for restore."
}

function verifyBackupAvailable () {
	out=$(find $backupPath -maxdepth 1 -type f | grep xtrabackup_info)
	verifyExecution "$?" "Backup doesn't exists. $out" true
        logInfo "[OK] Found backup in $backupPath"
}

function verifyMemory () {
	memoryAvailable=$(free -b | grep Mem | awk '{print $4+$7}')
	percent=$(printf "%.0f" $(echo $memoryAvailable*0.8 | bc))
	if [ $percent -lt 536870912  ]; then
		verifyExecution "1" "Not enough memory available to fire up a mysql instance" true
	fi
	logInfo "Memory available for restore"
}

function restoreBackup (){

	logInfo "Enter restore backup function"
	mkdir -p $restorePath &> /dev/null
	rm -rf $restorePath/* &> /dev/null
	logInfo "Created directory $restorePath"
	restoreCommand="innobackupex --apply-log "

	if [ $isCompress -eq 1 ]; then
		logInfo "Backup compressed. Start to decompress: innobackupex --decompress $backupPath"
		out=$(innobackupex --decompress $backupPath 2>&1)
		verifyExecution "$?" "Failure while decompressing the backup. $out" true
		logInfo "Backup decompressed"
	elif [ $isCompact -eq 1 ]; then
		logIngo "Backup compact. Adding --rebuild-indexes parameter"
		restoreCommand="$restoreCommand --rebuild-indexes "
	fi

	logInfo "Preparing backup: $restoreCommand $backupPath"	
	out=$($restoreCommand $backupPath 2>&1)
	verifyExecution "$?" "Failure while preparing backup. $out" true
        logInfo "Backup prepared"

	logInfo "Copy files to datadir: $restorePath"
	out=$(cp -R $backupPath/* $restorePath/ 2>&1)
	verifyExecution "$?" "Cannot copy files to $restorePath. $out" true
	logInfo "Files copied to datadir $restorePath"

	logInfo "Change owner of files to mysql"
	chown -R mysql:mysql $restorePath/
	logInfo "Datadir owned by mysql (chown -R mysql:mysql $restorePath)/"
}

function verifyPortFree () {
	out=$(netstat -tpa | grep 3310)
	if [ $? -eq 0 ]; then
		verifyExecution "1" "Port 3310 busy. Shutdown stalled mysql instance in port 3310 and retry" true
	fi
	logInfo "Port 3310 available"
}

function launchMysql () {

	logInfo "Launching small instance of MySQL"
	sed -i '/innodb_fast_checksum/d' $restorePath/backup-my.cnf

	out=$($(which mysqld) --defaults-file=${restorePath}/backup-my.cnf --basedir=/usr --datadir=$restorePath --plugin-dir /usr/lib/mysql/plugin --user=mysql --log-error=${restorePath}/error.log --pid-file=${restorePath}/mysqld.pid --explicit_defaults_for_timestamp=true --socket=${restorePath}/mysqld.sock --port=3310 2>&1 &)
	verifyExecution "$?" "Cannot launch MySQL instance. $out. More info: ${restorePath}/error.log" true
	logInfo "MySQL instance launched: $(which mysqld) --defaults-file=${restorePath}/backup-my.cnf --basedir=/usr --datadir=$restorePath --plugin-dir /usr/lib/mysql/plugin --user=mysql --log-error=${restorePath}/error.log --pid-file=${restorePath}/mysqld.pid --explicit_defaults_for_timestamp=true --socket=${restorePath}/mysqld.sock --port=3310 2>&1"
}

function verify () {
	verifyXtrabackup
	verifyMysqlBin
	verifyBackupAvailable
	verifySpace
	verifyMemory
}

function sanitize () {
	echo "Here is where the magic happens"
}

function logicalBackup () {
	echo "Do the mysqldump"
}

function shutdownMysql () {
	sleep 10 #temporal
	mysqladmin --socket=${restorePath}/mysqld.sock shutdown
	logInfo "MySQL instance shutdown."
}

if [ -z "$1" ]; then
	msg="Backup path wasn't provided. Default path ($backupPath) will be used and most recent backup restored"
	logInfo "$msg"
	backupPath=$(find $backupPath -maxdepth 1 -type d | sort -nr | head -n1)
        logInfo "$backupPath will be restored"
else
	backupPath=$(echo "$1")
	if [ ! -e $backupPath ]; then
		msg="$backupPath is not a file!"
		verifyExecution "1" "$msg" true
		echo $msg
		exit 1
	fi
fi

setLockFile
verify
restoreBackup
launchMysql
sanitize
logicalBackup
shutdownMysql
