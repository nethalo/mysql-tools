#!/bin/bash
#
# Daniel Guzman Burgos
# daniel.guzman.burgos@percona.com
#

readonly tinyint=127
readonly tinyint_unsigned=255
readonly smallint=32767
readonly smallint_unsigned=65535
readonly mediumint=8388607
readonly mediumint_unsigned=16777215
readonly int=2147483647
readonly int_unsigned=4294967295
readonly bigint=9223372036854775807
readonly bigint_unsigned=18446744073709551615

# critical percentage
readonly threshold=90 

tempDbFile="/tmp/dbs.txt"

function destructor () {
	rm -f $tempDbFile
}

#trap destructor EXIT INT TERM

function getLimitValue() {
	limitvalue_tinyint=$(echo "scale=0; $tinyint * $threshold/100" | bc)
	limitvalue_tinyint_unsigned=$(echo "scale=0; $tinyint_unsigned * $threshold/100" | bc)
	limitvalue_smallint=$(echo "scale=0; $smallint * $threshold/100" | bc)
	limitvalue_smallint_unsigned=$(echo "scale=0; $smallint_unsigned * $threshold/100" | bc)
	limitvalue_mediumint=$(echo "scale=0; $mediumint * $threshold/100" | bc)
	limitvalue_mediumint_unsigned=$(echo "scale=0; $mediumint_unsigned * $threshold/100" | bc)
	limitvalue_int=$(echo "scale=0; $int * $threshold/100" | bc)
	limitvalue_int_unsigned=$(echo "scale=0; $int_unsigned * $threshold/100" | bc)
}

function noIS () {
	mysql -A -N -e"show databases" | egrep -vi "information_schema|mysql|performance_schema" > $tempDbFile

	for k in $(cat $tempDbFile); do
		for j in $(mysql -N -e"show tables from $k"); do

			fieldData=""
			fieldData=$(mysql -A -N -e"show create table ${k}.${j}\G" | grep -i auto_increment | head -n1)
			if [[ "$fieldData" == "" || "$fieldData" == "NULL" ]]; then
				continue
			fi

			fieldName=$(echo $fieldData | awk '{print $1}')
			inttype=$(echo $fieldData | awk '{print $2}' | awk -F\( '{print $1}')

			if [[ $fieldData == *"unsigned"* ]]; then
		  		inttype=${inttype}_unsigned 
			fi

			i="SELECT MAX($fieldName) FROM \`${k}\`.\`${j}\`;"
			out=$(mysql -N -e"$i")
			value=$(echo $out | awk '{print $1}')

			#Table empty
			if [ "$value" == "NULL" ]; then
				continue;
			fi
			
			chechIntMax

		done
	done
}

function withIS () {
	QUERY="SELECT 
	CONCAT(\"SELECT MAX(\`\",COLUMN_NAME,\"\`), '\",COLUMN_TYPE,\"' FROM \`\",COLUMNS.TABLE_SCHEMA,\"\`.\`\",TABLE_NAME,\"\`;\")
FROM 
	INFORMATION_SCHEMA.COLUMNS
INNER JOIN INFORMATION_SCHEMA.TABLES using(TABLE_NAME) 
	WHERE TABLES.ENGINE IN ('innodb','myisam')
	AND COLUMNS.EXTRA = 'auto_increment';"

IFS='
'

	for i in $(mysql -N -e"$QUERY"); do
		out=$(mysql -N -e"$i")
		value=$(echo $out | awk '{print $1}')
		inttype=$(echo $out | awk '{print $2}' | awk -F\( '{print $1}')

		#Table empty
		if [ "$value" == "NULL" ]; then
			continue;
		fi

		# Unsigned used
		if [[ $out == *"unsigned"* ]]; then
	  		inttype=${inttype}_unsigned 
		fi

		chechIntMax

	done

}

function chechIntMax () {
	maxvalue=$(eval echo \$$inttype)

	# Bigint unsigned is already the biggest value so no need to check
	if [[ "$inttype" == "bigint_unsigned" || "$inttype" == "bigint" ]]; then 
		#Bigint signed is verified by the amount of digits in the max value
		if [ "$inttype" == "bigint" ]; then
			digits=$(echo ${#value})
			if [ $digits -gt 17 ]; then
				echo "AUTO INC value ($value) close to exhaustion (Max Value: $maxvalue) $i"
			fi
		fi;
		continue;
	fi

	limitvalue=$(eval echo "limitvalue_$inttype")
	limitvalue=$(eval echo \$$limitvalue)

	if [ $value -gt $limitvalue ]; then
		echo "AUTO INC value ($value) close to exhaustion (Max Value: $maxvalue) $i"
	fi
}

getLimitValue

if [[ "$1" == "I_S" || "$1" == "i_s" ]]; then
	withIS 
else
	noIS
fi
