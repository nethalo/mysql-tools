#!/bin/bash
query="set session group_concat_max_len=2048; select concat(digest_text,'dash', round(sum_timer_wait/ 1000000000000, 6),'\n') from performance_schema.events_statements_summary_by_digest order by sum_timer_wait desc limit 20;"
IFS="
"
for i in $(mysql -Nr -e"$query"); do
        digest=$(echo ${i%%dash*})
        digest=${digest%%,*}
        digest=$(echo $digest | tr -d "\`")
        digest=$(echo $digest | tr " " "_")
        digest=$(echo $digest | tr -d "?")
        digest=$(echo $digest | tr "." "-")
        digest=$(echo $digest | tr "(" "_")
        digest=$(echo $digest | tr ")" "_")
        value=$(echo ${i##*dash})
        echo "mysql.rds.$digest $value $(date +%s)" | nc -w 1 localhost 2003
done
