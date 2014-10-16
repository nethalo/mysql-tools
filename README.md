# MySQL Tools

Collection of scripts that enhance another MySQL tools :)

## Load Data
The load_data.sh is a bash code script that allows you to:

* Load data in **Parallel** by a number of user-defined threads
* Protect against **Performance** degradation. The script checks on each iteration for the status variable *Threads_running* and the current *Checkpoint age* in order to keep thing under a defined threshold.
* Load data in small transactions.

### Requirements: 
* This script acts as a wrapper around the [pt-fifo-split](http://www.percona.com/doc/percona-toolkit/2.2/pt-fifo-split.html "pt-fifo-split") tool from the Percona Toolkit. You will need to have this tool in your server.
* The "split" tool from linux [Coreutils](http://www.gnu.org/software/coreutils/ "Coreutils"), version 8.8 or greater is needed. You can use the one that i have in this repo: [split](https://github.com/nethalo/mysql-tools/blob/master/split "Split") or compile one yourself. The reason for this is that the script uses the **--number** parameter

### Settings

This values can be modified to suit better your needs.

* **readonly max_running_threads=10** After this value, the script will pause the data load and will resume after the value of Threads_running is lower than the one defined. You will need to check with: SHOW STATUS LIKE 'Threads_running' a good value for your server
* **readonly checkpoint_threshold_pct=70** The script will run only if the checkpoint age (Amount of transactions still in InnoDB Log File but not on the tablespace) is below 70% of total available size
* **readonly fifoLines=1000** The number of lines that pt-fifo-split will use per read.
* **readonly CHUNKS=8** The number of **Parallel** running threads. This shouldn't be more than the available CPU cores.

Also:

* **user=root** The MySQL user that the script will use to connect to the database. 
The script relies that the password is defined in a .my.cnf file under the home directory of the linux user.
Example, if the user is root:

``` 
File name: /root/.my.cnf
File permission: chown 644 /root/.my.cnf
File contents:
[client]
user=root
password=p@$$w0rd
``` 
* **database=sakila** The database name where the destination table exists.

### Run
To run the script you only need to execute this line:

``` 
./load_data.sh "/path/to/the/file"
``` 

Right now, the script can only load non-extended INSERT files, which means, files with this kind of inserts:
``` 
INSERT INTO `actor` VALUES (1,'PENELOPE','GUINESS','2006-02-15 02:34:33');
INSERT INTO `actor` VALUES (2,'NICK','WAHLBERG','2006-02-15 02:34:33');
INSERT INTO `actor` VALUES (3,'ED','CHASE','2006-02-15 02:34:33');
INSERT INTO `actor` VALUES (4,'JENNIFER','DAVIS','2006-02-15 02:34:33');
``` 

Coming soon, "LOAD DATA" types
