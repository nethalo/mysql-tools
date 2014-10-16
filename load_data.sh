#!/bin/bash
#
# Load data to MySQL in a controlled way
# Daniel Guzman Burgos
# daniel.guzman.burgos@percona.com

set -o pipefail

readonly max_running_threads=10;
readonly checkpoint_threshold_pct=70
readonly fifoLines=1000
readonly CHUNKS=8

user=root
database=sakila

function destructor () {
	mysql -u$user -e"SET GLOBAL innodb_old_blocks_time = 0"
}

trap destructor INT TERM EXIT

function getLogFileSize () {
        local SIZE=$(mysql -N -e"show variables like 'innodb_log_file_size'" | awk '{print $2}')
        local GROUP=$(mysql -N -e"show variables like 'innodb_log_files_in_group'" | awk '{print $2}')
        totalBytes=$(($SIZE*$GROUP))
}

function getCheckPct () {
        chkckpointLimit=$(echo "${checkpoint_threshold_pct}/100*10485760" | bc -l | awk -F. '{print $1}')
}

function checkThreads () {
        local currentThreadsRunning=$(mysql -N -e"show global status like 'Threads_running'" | awk '{print $2}')
        while [ $currentThreadsRunning -gt $max_running_threads ]; do
                echo "Waiting until Threads_running go back to lower than $max_running_threads. Currently: $currentThreadsRunning ....";
                sleep 1
                local currentThreadsRunning=$(mysql -N -e"show global status like 'Threads_running'" | awk '{print $2}')
        done
}

function monitorCheckpoint () {
        local currentCheckpoint=$(mysql -N -e"show status like 'Innodb_checkpoint_age'" | awk '{print $2}')
        while [ $currentCheckpoint -gt $chkckpointLimit ]; do
                echo "Waiting until checkpoint age becomes lower than $chkckpointLimit bytes. Currently $currentCheckpoint ...."
                sleep 1
                local currentCheckpoint=$(mysql -N -e"show status like 'Innodb_checkpoint_age'" | awk '{print $2}')
        done
}

function loadData () {

        if [ -z "$1" ]; then
                echo "Error: No file specified: ./load_data.sh \"/path/to/file\""
                exit 1
        fi

	fifoFile=/tmp/dani_$2

        /usr/bin/pt-fifo-split --force --fifo $fifoFile --lines $fifoLines "$1" &
        sleep 1;
        
	mysql -u$user -e"SET GLOBAL innodb_old_blocks_time = 1000"
        while [ -p "$fifoFile" ]; do
                echo "Loading data from part $1 using fifo $fifoFile ..."
                cat $fifoFile | mysql -u$user $database 2>&1
                checkThreads
                monitorCheckpoint
        done
        mysql -u$user -e"SET GLOBAL innodb_old_blocks_time = 0"
	
	trap - INT TERM EXIT
}

function loadDataParallel () {
	
	clear

	if [ -z "$1" ]; then
                echo "Error: No file specified: ./load_data.sh \"/path/to/file\""
                exit 1
        fi

	echo "Start to load data in parallel"
	
	DATAFILE=$1	
        SPLITTED=/tmp/filepart

        local TTL=1
        local WATCHDOG_TIME=$((3600*$TTL))

        /usr/bin/split --number=l/$CHUNKS --numeric-suffixes --suffix-length=1 $DATAFILE $SPLITTED
	mysql -u$user -e"SET GLOBAL innodb_old_blocks_time = 1000"

        for d in $(seq $CHUNKS) ; do
		echo "Launching $0 --single-load ${SPLITTED}$(($d-1)) $d"
		$0 --single-load "${SPLITTED}$(($d-1))" "$d" &
                pid[$d]=$!
        done

        WATCHDOG_INIT=$(date +%s)
        while [ "${#pid[@]}" -ne 0 ]; do
                count=0
                for p in $(echo ${pid[@]}); do
                        kill -0 $p > /dev/null 2>&1
                        if [ $? -ne 0 ]; then
                                pid=(${pid[@]:0:$count} ${pid[@]:$(($count + 1))})
                        fi
                        count=$(($count+1))
                done

                WATCHDOG_NOW=$(date +%s)
                UPTIME=$(($WATCHDOG_NOW-$WATCHDOG_INIT))

                if [ $UPTIME -ge $WATCHDOG_TIME ]; then
                        echo "Timeout. ${TTL} hours running. Load data interrupted"
                        exit 1
                fi

                sleep 1
        done

}

getLogFileSize
getCheckPct
checkThreads
monitorCheckpoint

if [ $1 == "--single-load" ]; then
	loadData "$2" "$3"
	exit
fi

loadDataParallel "$1"
