# **Performance Schema / Memory Footprint**

[TOC]

## Performance Schema in a nutshell

Performance Schema is a mechanism to collect and report run time statistics for running MySQL server. These statistics are stored-in and fetched-from internal memory buffers.

## P_S memory footprint

### What's currently available in 5.6?

In MySQL 5.6, memory for these buffers is allocated during MySQL server startup with either user specified configuration values or with default values that autosize. Once the server has started, the size of the buffers is fixed and performance_schema does not do any additional memory allocation or freeing during execution.

#### Limitations of fixed memalloc

- Significant amount of allocated buffer is left unused if less instances of instrument are encountered.
- Amount allocated is not sufficient and performance_schema starts loosing further statistics if more instances of instrument are encountered.

### What's new in 5.7?

In MySQL 5.7 memory allocation for Performance Schema buffers doesn’t happen at server start-up but is instead based on the actual runtime requirement.

As of MySQL 5.7.6, the memory model allocates less memory by default under most circumstances:

- May allocate memory at server startup

- May allocate additional memory during server operation

- Never free memory during server operation (although it might be recycled)

- Free all memory used at shutdown

Consumption scales with server load. Memory used depends on the load actually seen, not the load estimated or explicitly configured for.

#### How to set memory allocation?

For the server variables (which control buffer size), you can now specify:

| Value | Description                              |
| ----- | ---------------------------------------- |
| 0     | To tell P_S not to collect stats thus no allocation for this buffer. |
| N     | To tell P_S to collect stats for maximum N instance only. Memory allocation happens as and when need arises. And this allocation continues until space for max (N here) instances is allocated. |
| -1    | To tell P_S take your own decision for maximum limit. As above, memory is allocated as and when need arises. This allocation continues until space for max (decided by P_S here) instances is allocated. |

With -1, as the Performance Schema collects data, memory is allocated in the corresponding buffer. The buffer size is unbounded, and may grow with the load.

With N, once the buffer size reaches N, no more memory is allocated. Data collected by the Performance Schema for this buffer is lost, and any corresponding “lost instance” counters are incremented.

#### How much memory the Performance Schema is using?

The Performance Schema allocates memory internally and associates each buffer with a dedicated instrument so that memory consumption can be traced to individual buffers.

Instruments named with the prefix memory/performance_schema/ expose how much memory is allocated for these internal buffers. 

The buffers are global to the server, so the instruments are displayed only in the **memory_summary_global_by_event_name** table, and not in other memory_summary_by_xxx_by_event_name tables.

Use this query:

```mysql
SELECT 
	*
FROM 
	performance_schema.memory_summary_global_by_event_name
WHERE EVENT_NAME LIKE 'memory/performance_schema/%';
```

```mysql
*************************** 1. row ***************************
                  EVENT_NAME: memory/performance_schema/file_instances
                 COUNT_ALLOC: 1
                  COUNT_FREE: 0
   SUM_NUMBER_OF_BYTES_ALLOC: 720896
    SUM_NUMBER_OF_BYTES_FREE: 0
              LOW_COUNT_USED: 0
          CURRENT_COUNT_USED: 1
             HIGH_COUNT_USED: 1
    LOW_NUMBER_OF_BYTES_USED: 0
CURRENT_NUMBER_OF_BYTES_USED: 720896
   HIGH_NUMBER_OF_BYTES_USED: 720896
```

For details about the fields, please see https://dev.mysql.com/doc/refman/5.7/en/memory-summary-tables.html

You can also use the **SHOW ENGINE PERFORMANCE_SCHEMA STATUS** command to inspect the internal operation of the Performance Schema code:

```mysql
mysql> pager grep "\.memory" | less
PAGER set to 'grep "\.memory" | less'
mysql> show engine performance_schema status;
| performance_schema | events_waits_history.memory                                 | 450560   |
| performance_schema | events_waits_history_long.memory                            | 176000   |
| performance_schema | (pfs_mutex_class).memory                                    | 51200    |
| performance_schema | (pfs_rwlock_class).memory                                   | 12800    |
| performance_schema | (pfs_cond_class).memory                                     | 20480    |
| performance_schema | (pfs_thread_class).memory                                   | 9600     |
| performance_schema | (pfs_file_class).memory                                     | 25600    |
| performance_schema | mutex_instances.memory                                      | 0        |
| performance_schema | rwlock_instances.memory                                     | 0        |
| performance_schema | cond_instances.memory                                       | 0        |
| performance_schema | threads.memory                                              | 950272   |
| performance_schema | file_instances.memory                                       | 720896   |
| performance_schema | (pfs_file_handle).memory                                    | 262144   |
| performance_schema | events_waits_summary_by_thread_by_event_name.memory         | 3473408  |
| performance_schema | (pfs_table_share).memory                                    | 1048576  |
| performance_schema | (pfs_table).memory                                          | 0        |
| performance_schema | setup_actors.memory                                         | 40960    |
| performance_schema | setup_objects.memory                                        | 57344    |
| performance_schema | (pfs_account).memory                                        | 90112    |
| performance_schema | events_waits_summary_by_account_by_event_name.memory        | 1736704  |
| performance_schema | events_waits_summary_by_user_by_event_name.memory           | 1736704  |
| performance_schema | events_waits_summary_by_host_by_event_name.memory           | 1736704  |
| performance_schema | (pfs_user).memory                                           | 81920    |
| performance_schema | (pfs_host).memory                                           | 73728    |
| performance_schema | (pfs_stage_class).memory                                    | 38400    |
| performance_schema | events_stages_history.memory                                | 266240   |
| performance_schema | events_stages_history_long.memory                           | 104000   |
| performance_schema | events_stages_summary_by_thread_by_event_name.memory        | 1228800  |
| performance_schema | events_stages_summary_global_by_event_name.memory           | 4800     |
| performance_schema | events_stages_summary_by_account_by_event_name.memory       | 614400   |
| performance_schema | events_stages_summary_by_user_by_event_name.memory          | 614400   |
| performance_schema | events_stages_summary_by_host_by_event_name.memory          | 614400   |
| performance_schema | (pfs_statement_class).memory                                | 38592    |
| performance_schema | events_statements_history.memory                            | 3665920  |
| performance_schema | events_statements_history_long.memory                       | 1432000  |
| performance_schema | events_statements_summary_by_thread_by_event_name.memory    | 9467904  |
| performance_schema | events_statements_summary_global_by_event_name.memory       | 36984    |
| performance_schema | events_statements_summary_by_account_by_event_name.memory   | 4733952  |
| performance_schema | events_statements_summary_by_user_by_event_name.memory      | 4733952  |
| performance_schema | events_statements_summary_by_host_by_event_name.memory      | 4733952  |
| performance_schema | events_statements_current.memory                            | 3665920  |
| performance_schema | (pfs_socket_class).memory                                   | 3200     |
| performance_schema | socket_instances.memory                                     | 0        |
| performance_schema | events_statements_summary_by_digest.memory                  | 2560000  |
| performance_schema | events_statements_summary_by_program.memory                 | 0        |
| performance_schema | session_connect_attrs.memory                                | 131072   |
| performance_schema | prepared_statements_instances.memory                        | 0        |
| performance_schema | (pfs_memory_class).memory                                   | 76800    |
| performance_schema | memory_summary_by_thread_by_event_name.memory               | 7372800  |
| performance_schema | memory_summary_global_by_event_name.memory                  | 28800    |
| performance_schema | memory_summary_by_account_by_event_name.memory              | 3686400  |
| performance_schema | memory_summary_by_user_by_event_name.memory                 | 3686400  |
| performance_schema | memory_summary_by_host_by_event_name.memory                 | 3686400  |
| performance_schema | metadata_locks.memory                                       | 0        |
| performance_schema | events_transactions_history.memory                          | 880640   |
| performance_schema | events_transactions_history_long.memory                     | 344000   |
| performance_schema | events_transactions_summary_by_thread_by_event_name.memory  | 22528    |
| performance_schema | events_transactions_summary_by_account_by_event_name.memory | 11264    |
| performance_schema | events_transactions_summary_by_user_by_event_name.memory    | 11264    |
| performance_schema | events_transactions_summary_by_host_by_event_name.memory    | 11264    |
| performance_schema | table_lock_waits_summary_by_table.memory                    | 0        |
| performance_schema | table_io_waits_summary_by_index_usage.memory                | 352256   |
| performance_schema | (history_long_statements_digest_token_array).memory         | 1024000  |
| performance_schema | (history_statements_digest_token_array).memory              | 2621440  |
| performance_schema | (current_statements_digest_token_array).memory              | 2621440  |
| performance_schema | (history_long_statements_text_array).memory                 | 1024000  |
| performance_schema | (history_statements_text_array).memory                      | 2621440  |
| performance_schema | (current_statements_text_array).memory                      | 2621440  |
| performance_schema | (statements_digest_token_array).memory                      | 5120000  |
| performance_schema | performance_schema.memory                                   | 89269176 |
```

Name values consist of two parts, which name an internal buffer and a buffer attribute, respectively. Interpret buffer names as follows:

- An internal buffer that is not exposed as a table is named within parentheses. Examples: (pfs_cond_class).size, (pfs_mutex_class).memory.

- An internal buffer that is exposed as a table in the performance_schema database is named after the table, without parentheses. Examples: events_waits_history.size, mutex_instances.count.

- A value that applies to the Performance Schema as a whole begins with performance_schema. Example: performance_schema.memory.

Buffer attributes have these meanings:

- **size** is the size of the internal record used by the implementation, such as the size of a row in a table. size values cannot be changed.

- **count** is the number of internal records, such as the number of rows in a table. count values can be changed using Performance Schema configuration options.

- For a table, **tbl_name**.memory is the product of size and count. For the Performance Schema as a whole, performance_schema.memory is the sum of all the memory used (the sum of all other memory values).

## P_S Memory metrics

### Memory tables

5 tables (5.7.11-4 Percona Server (GPL), Release '4', Revision '5c940e1'):

```mysql
mysql> show tables like '%memory%';
+-----------------------------------------+
| Tables_in_performance_schema (%memory%) |
+-----------------------------------------+
| memory_summary_by_account_by_event_name |
| memory_summary_by_host_by_event_name    |
| memory_summary_by_thread_by_event_name  |
| memory_summary_by_user_by_event_name    |
| memory_summary_global_by_event_name     |
+-----------------------------------------+
5 rows in set (0.00 sec)
```

### Memory instruments

391 memory instruments (5.7.11-4 Percona Server (GPL), Release '4', Revision '5c940e1')

```mysql
mysql> select substring_index(name,'/',2), count(*) from performance_schema.setup_instruments where name like 'memory%' group by 1 with rollup;
+-----------------------------+----------+
| substring_index(name,'/',2) | count(*) |
+-----------------------------+----------+
| memory/archive              |        2 |
| memory/blackhole            |        1 |
| memory/client               |        7 |
| memory/csv                  |        5 |
| memory/innodb               |       92 |
| memory/keyring              |        1 |
| memory/memory               |        5 |
| memory/myisam               |       21 |
| memory/myisammrg            |        2 |
| memory/mysys                |       21 |
| memory/partition            |        3 |
| memory/performance_schema   |       70 |
| memory/sql                  |      157 |
| memory/vio                  |        4 |
| NULL                        |      391 |
+-----------------------------+----------+
15 rows in set (0.00 sec)
```

Let's enable all the consumers:

```mysql
mysql> update setup_consumers set enabled = 'yes' ;
Query OK, 10 rows affected (0.00 sec)
Rows matched: 15  Changed: 10  Warnings: 0
```

By default, only 70 memory instruments are enabled:

```Mysql
mysql> select count(*) from setup_instruments where name like 'memory%' and enabled = 'yes';
+----------+
| count(*) |
+----------+
|       70 |
+----------+
1 row in set (0.00 sec)
```

Let's enable all of them:

```mysql
mysql> update setup_instruments set enabled = 'yes' where name like 'memory%';
Query OK, 321 rows affected (0.00 sec)
Rows matched: 391  Changed: 321  Warnings: 0
```

Now, to get the statistics, we could just query the **p_s.memory_%** tables OR we could use the Sys Schema!

## Using Sys Schema

Sys Schema comes by default in 5.7 and have 5 views related to **Memory:**

- memory_by_host_by_current_bytes
- memory_by_thread_by_current_bytes
- memory_by_user_by_current_bytes
- memory_global_by_current_bytes
- memory_global_total

#### memory_by_host_by_current_bytes

Summarizes memory use by host using the 5.7 Performance Schema instrumentation. When the host found is NULL, it is assumed to be a local "background" thread.

```mysql
mysql> select * from memory_by_host_by_current_bytes;
+------------+--------------------+-------------------+-------------------+-------------------+-----------------+
| host       | current_count_used | current_allocated | current_avg_alloc | current_max_alloc | total_allocated |
+------------+--------------------+-------------------+-------------------+-------------------+-----------------+
| localhost  |                833 | 1.56 MiB          | 1.92 KiB          | 805.47 KiB        | 1.72 GiB        |
| background |                 52 | 24.14 KiB         | 475 bytes         | 16.02 KiB         | 3.88 MiB        |
+------------+--------------------+-------------------+-------------------+-------------------+-----------------+
2 rows in set (0.00 sec)
```

It's based on the table **performance_schema.memory_summary_by_host_by_event_name**

#### memory_by_thread_by_current_bytes

Summarizes memory use by threads using the 5.7 Performance Schema instrumentation.

```mysql
mysql> select * from sys.memory_by_thread_by_current_bytes limit 10;
+-----------+----------------------------+--------------------+-------------------+-------------------+-------------------+-----------------+
| thread_id | user                       | current_count_used | current_allocated | current_avg_alloc | current_max_alloc | total_allocated |
+-----------+----------------------------+--------------------+-------------------+-------------------+-------------------+-----------------+
|        29 | root@localhost             |                517 | 1.46 MiB          | 2.89 KiB          | 805.47 KiB        | 226.81 MiB      |
|        40 | root@localhost             |                 13 | 22.84 KiB         | 1.76 KiB          | 16.01 KiB         | 25.48 MiB       |
|        38 | root@localhost             |                 12 | 22.49 KiB         | 1.87 KiB          | 16.01 KiB         | 25.50 MiB       |
|        39 | root@localhost             |                 12 | 22.49 KiB         | 1.87 KiB          | 16.01 KiB         | 24.00 MiB       |
|        37 | root@localhost             |                 11 | 22.15 KiB         | 2.01 KiB          | 16.01 KiB         | 23.92 MiB       |
|        25 | innodb/dict_stats_thread   |                 30 | 5.00 KiB          | 171 bytes         | 4.47 KiB          | 1.71 MiB        |
|         3 | innodb/io_write_thread     |                  0 | 0 bytes           | 0 bytes           | 0 bytes           | 0 bytes         |
|         4 | innodb/io_write_thread     |                  0 | 0 bytes           | 0 bytes           | 0 bytes           | 0 bytes         |
|         5 | innodb/io_write_thread     |                  0 | 0 bytes           | 0 bytes           | 0 bytes           | 0 bytes         |
|         6 | innodb/page_cleaner_thread |                  0 | 0 bytes           | 0 bytes           | 0 bytes           | 3.48 KiB        |
+-----------+----------------------------+--------------------+-------------------+-------------------+-------------------+-----------------+
10 rows in set (0.10 sec)
```

Based on the tables **performance_schema.memory_summary_by_thread_by_event_name** and **performance_schema.threads.**

#### memory_by_user_by_current_bytes

Summarizes memory use by user using the 5.7 Performance Schema instrumentation.

```mysql
mysql> select * from memory_by_user_by_current_bytes;
+------------+--------------------+-------------------+-------------------+-------------------+-----------------+
| user       | current_count_used | current_allocated | current_avg_alloc | current_max_alloc | total_allocated |
+------------+--------------------+-------------------+-------------------+-------------------+-----------------+
| root       |                835 | 1.57 MiB          | 1.92 KiB          | 805.47 KiB        | 2.41 GiB        |
| background |                 66 | 26.45 KiB         | 410 bytes         | 16.02 KiB         | 7.00 MiB        |
+------------+--------------------+-------------------+-------------------+-------------------+-----------------+
2 rows in set (0.01 sec)
```

Based on the table **performance_schema.memory_summary_by_user_by_event_name**

#### memory_global_by_current_bytes

Shows the current memory usage within the server globally broken down by allocation type.

Example of all the memory allocated by sql instruments:

```mysql
mysql> select * from memory_global_by_current_bytes where event_name like 'memory/sql%';
+---------------------------------------+---------------+---------------+-------------------+------------+------------+----------------+
| event_name                            | current_count | current_alloc | current_avg_alloc | high_count | high_alloc | high_avg_alloc |
+---------------------------------------+---------------+---------------+-------------------+------------+------------+----------------+
| memory/sql/sp_head::main_mem_root     |            73 | 805.47 KiB    | 11.03 KiB         |         83 | 885.31 KiB | 10.67 KiB      |
| memory/sql/TABLE_SHARE::mem_root      |           312 | 581.69 KiB    | 1.86 KiB          |        315 | 584.89 KiB | 1.86 KiB       |
| memory/sql/TABLE                      |           221 | 294.98 KiB    | 1.33 KiB          |        231 | 604.67 KiB | 2.62 KiB       |
| memory/sql/Filesort_buffer::sort_keys |             1 | 255.90 KiB    | 255.90 KiB        |          1 | 255.90 KiB | 255.90 KiB     |
| memory/sql/String::value              |            16 | 64.11 KiB     | 4.01 KiB          |         30 | 130.88 KiB | 4.36 KiB       |
| memory/sql/thd::main_mem_root         |             6 | 63.75 KiB     | 10.62 KiB         |         74 | 4.64 MiB   | 64.24 KiB      |
| memory/sql/THD::sp_cache              |             1 | 7.98 KiB      | 7.98 KiB          |          1 | 7.98 KiB   | 7.98 KiB       |
| memory/sql/THD::variables             |             4 | 512 bytes     | 128 bytes         |          4 | 512 bytes  | 128 bytes      |
| memory/sql/TABLE::sort_io_cache       |             1 | 280 bytes     | 280 bytes         |          1 | 280 bytes  | 280 bytes      |
| memory/sql/acl_cache                  |             4 | 209 bytes     | 52 bytes          |          4 | 209 bytes  | 52 bytes       |
| memory/sql/MYSQL_LOCK                 |             5 | 176 bytes     | 35 bytes          |          5 | 200 bytes  | 40 bytes       |
| memory/sql/dboptions_hash             |             1 | 48 bytes      | 48 bytes          |          1 | 48 bytes   | 48 bytes       |
| memory/sql/THD::db                    |             5 | 36 bytes      | 7 bytes           |          5 | 36 bytes   | 7 bytes        |
+---------------------------------------+---------------+---------------+-------------------+------------+------------+----------------+
13 rows in set (0.00 sec)
```

And for InnoDB:

```mysql
mysql> select * from memory_global_by_current_bytes where event_name like 'memory/innodb%';
+-------------------------------------+---------------+---------------+-------------------+------------+------------+----------------+
| event_name                          | current_count | current_alloc | current_avg_alloc | high_count | high_alloc | high_avg_alloc |
+-------------------------------------+---------------+---------------+-------------------+------------+------------+----------------+
| memory/innodb/mem0mem               |            56 | 82.06 KiB     | 1.47 KiB          |        148 | 348.85 KiB | 2.36 KiB       |
| memory/innodb/trx0undo              |           202 | 69.44 KiB     | 352 bytes         |        202 | 69.44 KiB  | 352 bytes      |
| memory/innodb/ha_innodb             |            14 | 5.06 KiB      | 370 bytes         |         15 | 5.96 KiB   | 407 bytes      |
| memory/innodb/os0event              |            14 | 1.86 KiB      | 136 bytes         |         27 | 3.59 KiB   | 136 bytes      |
| memory/innodb/fil0fil               |             2 | 632 bytes     | 316 bytes         |         10 | 4.06 MiB   | 416.09 KiB     |
| memory/innodb/dict0dict             |             3 | 384 bytes     | 128 bytes         |          7 | 1.08 KiB   | 157 bytes      |
| memory/innodb/std                   |             6 | 296 bytes     | 49 bytes          |         22 | 385.73 KiB | 17.53 KiB      |
| memory/innodb/read0read             |             1 | 280 bytes     | 280 bytes         |          1 | 280 bytes  | 280 bytes      |
| memory/innodb/trx_sys_t::rw_trx_ids |             1 | 88 bytes      | 88 bytes          |          2 | 144 bytes  | 72 bytes       |
+-------------------------------------+---------------+---------------+-------------------+------------+------------+----------------+
9 rows in set (0.01 sec)
```

This view is based on the table **performance_schema.memory_summary_global_by_event_name**

#### memory_global_total

Shows the total memory usage within the server globally.

```
mysql> select * from memory_global_total;
+-----------------+
| total_allocated |
+-----------------+
| 96.91 MiB       |
+-----------------+
1 row in set (0.01 sec)
```

Based on the **performance_schema.memory_summary_global_by_event_name** table.

## More info

- http://mysqlserverteam.com/new-in-mysql-5-7-performance-schema-scalable-memory-allocation/
- https://dev.mysql.com/doc/refman/5.7/en/performance-schema-memory-model.html
- https://dev.mysql.com/doc/refman/5.7/en/memory-summary-tables.html
- https://dev.mysql.com/doc/refman/5.7/en/show-engine.html

