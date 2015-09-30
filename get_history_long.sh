#!/bin/bash

clear
counter=0
SLOW_LOG_CUSTOM=/root/log.out
rm -f $SLOW_LOG_CUSTOM

while true; do

        THREADS=$(mysql -N -e"SELECT t.thread_id FROM performance_schema.events_statements_history inner join performance_schema.threads t where t.PROCESSLIST_ID != connection_id() group by thread_id;")
        if [ $counter -eq 0 ]; then
                for k in $(echo $THREADS); do
                        OLD_EVENT[$k]=0
                done
        fi
        counter=1

        for i in $(echo $THREADS); do
                MAX_EVENT=$(mysql -N -e"SELECT IFNULL(max(event_id),0) FROM performance_schema.events_statements_history where thread_id = "$i)
                if [[ ! ${OLD_EVENT[$i]} ]]; then OLD_EVENT[$i]=0; fi
                if [ $MAX_EVENT -gt ${OLD_EVENT[$i]} ]; then
                        SQL="SELECT CONCAT_WS(
'','# Time: ', date_format(CURDATE(),'%y%m%d'),' ',TIME_FORMAT(NOW(6),'%H:%i:%s.%f'),'\n'
,'# User@Host: ',t.PROCESSLIST_USER,'[',t.PROCESSLIST_USER,'] @ ',PROCESSLIST_HOST,' []  Id: ',t.PROCESSLIST_ID,'\n'
,'# Schema: ',CURRENT_SCHEMA,'  Last_errno: ',MYSQL_ERRNO,'  ','\n'
,'# Query_time: ',ROUND(s.TIMER_WAIT / 1000000000000, 6),' Lock_time: ',ROUND(s.LOCK_TIME / 1000000000000, 6),'  Rows_sent: ',ROWS_SENT,'  Rows_examined: ',ROWS_EXAMINED,'  Rows_affected: ',ROWS_AFFECTED,'\n'
,'# Tmp_tables: ',CREATED_TMP_TABLES,'  Tmp_disk_tables: ',CREATED_TMP_DISK_TABLES,'  ','\n'
,'# Full_scan: ',IF(SELECT_SCAN=0,'No','Yes'),'  Full_join: ',IF(SELECT_FULL_JOIN=0,'No','Yes'),'  Tmp_table: ',IF(CREATED_TMP_TABLES=0,'No','Yes'),'  Tmp_table_on_disk: ',IF(CREATED_TMP_DISK_TABLES=0,'No','Yes'),'\n'
, t.PROCESSLIST_INFO,';') FROM performance_schema.events_statements_history_long s inner join performance_schema.threads t using (thread_id) WHERE t.thread_id = "$i" AND EVENT_ID BETWEEN "${OLD_EVENT[$i]}" AND "$MAX_EVENT" ORDER BY TIMER_END desc;"
                        #echo $SQL
                        mysql -Nr -e"$SQL" >> $SLOW_LOG_CUSTOM
                        unset OLD_EVENT[$i]
                        OLD_EVENT[$i]=$(echo $MAX_EVENT)
                fi
        done
done
