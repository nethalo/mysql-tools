#!/bin/bash
#
# Load data to MySQL in a controlled way
# Daniel Guzman Burgos
# daniel.guzman.burgos@percona.com

set -o pipefail
clear

readonly max_running_threads=10;
readonly checkpoint_threshold_pct=60
readonly fifoFile=/tmp/dani

user=root
database=sakila

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

        /usr/bin/pt-fifo-split --force --fifo $fifoFile --lines 10 "$1" &
        sleep 1;
        mysql -u$user -e"SET GLOBAL innodb_old_blocks_time = 1000"
        while [ -p "$fifoFile" ]; do
                echo "Loading data ..."
                cat $fifoFile | mysql -u$user $database 2>&1
                checkThreads
                monitorCheckpoint
        done
        mysql -u$user -e"SET GLOBAL innodb_old_blocks_time = 0"
}

getLogFileSize
getCheckPct
checkThreads
monitorCheckpoint
loadData "$1"
