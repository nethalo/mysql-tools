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
restorePath="/root"
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

function verifySpace () {
	spaceOnDisk=$(df -P ${restorePath} | tail -1 | awk '{print $4*1024}')
	verifyExecution "$?" "Cannot find space available on disk $restorePath" true
	backupSize=$(du -sb $backupPath | awk '{print $1}')
	verifyExecution "$?" "Cannot find backup size for $backupPath" true
	type=$(file -bi $backupPath/xtrabackup_info* | head -n1)
	verifyExecution "$?" "Cannot find file $backupPath/xtrabackup_info. No way to find if is compressed or not. Space available might not be enough. Run at your own risk!"
	if [[ $type != *"text"* ]]; then
		logInfo "Compressed backup"
		backupSize=$(($backupSize*43))
	fi
	out=$(cat $backupPath/xtrabackup_checkpoints | grep full-backuped)
	verifyExecution "$?" "Backup is not full backup." true
	out=$(cat $backupPath/xtrabackup_checkpoints | grep compact | grep 1)
	if [ $? -eq 0 ]; then
		logInfo "Compact backup"
		backupSize=$( printf "%.0f" $(echo $backupSize*1.02 | bc))
	else
		logInfo "Regular full backup (not compressed, not compact)"
	fi

	percent=$(printf "%.0f" $(echo $spaceOnDisk*0.9 | bc))
	if [ $backupSize -gt $percent ]; then
		verifyExecution "$?" "Not enough space in disk for restore." true
	fi
	logInfo "Space available for restore."
}

function verifyBackupAvailable () {
	out=$(find $backupPath -maxdepth 1 -type f | grep xtrabackup_info)
	verifyExecution "$?" "Backup doesn't exists" true
        logInfo "[OK] Found backup in $backupPath"
}

function verify () {
	verifyXtrabackup
	verifyBackupAvailable
	verifySpace
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
