# 目录
*   基础知识



## 1.基础知识
### 1.1 使用GDB分析PostgreSQL
*   How to Analyze a PostgreSQL Crash Dump File

### 各种日志
* 连接日志 (log_connections)
```
2021-12-31 22:10:04 CST [140384456275712]: user=[unknown],db=[unknown],app=[unknown],client=  0 [BACKEND] LOG:  connection received: host=VM-16-10-centos port=58128
2021-12-31 22:10:04 CST [140384456275712]: user=vastbase,db=postgres,app=[unknown],client=VM-16-10-centos  0 [BACKEND] LOG:  connection authorized: user=vastbase database=postgres
2021-12-31 22:10:04 CST [140384286467840]: user=vastbase,db=postgres,app=gs_clean,client=VM-16-10-centos  0 [BACKEND] LOG:  statement: select name, setting from pg_settings where name in ('
connection_info')
2021-12-31 22:10:04 CST [140384329529088]: user=vastbase,db=postgres,app=gs_clean,client=VM-16-10-centos  0 [BACKEND] LOG:  statement: SET connection_info = '{"driver_name":"libpq","driver_
version":"(Vastbase G100 V2.2 (Build 5.8.3547)) compiled at 2021-10-14 15:46:14 commit 0 last mr  "}'
2021-12-31 22:10:04 CST [140384303249152]: user=vastbase,db=postgres,app=gs_clean,client=VM-16-10-centos  0 [BACKEND] LOG:  statement: SET xc_maintenance_mode = on;
2021-12-31 22:10:04 CST [140384439494400]: user=vastbase,db=postgres,app=gs_clean,client=VM-16-10-centos  0 [BACKEND] LOG:  statement: SET enable_parallel_ddl = off;
2021-12-31 22:10:04 CST [140384392963840]: user=vastbase,db=postgres,app=gs_clean,client=VM-16-10-centos  0 [BACKEND] LOG:  statement: SELECT NSPNAME FROM PG_NAMESPACE WHERE NSPNAME LIKE 'p
g_temp_%'
2021-12-31 22:10:04 CST [140384409745152]: user=vastbase,db=postgres,app=gs_clean,client=VM-16-10-centos  0 [BACKEND] LOG:  statement: SELECT SESSIONID, TEMPID, TIMELINEID FROM PG_DATABASE 
D, PG_STAT_GET_ACTIVITY_FOR_TEMPTABLE() AS S WHERE S.DATID = D.OID AND D.DATNAME = 'postgres'
2021-12-31 22:10:04 CST [140382860994304]: user=vastbase,db=postgres,app=gs_clean,client=VM-16-10-centos  0 [BACKEND] LOG:  disconnection: session time: 0:00:00.036 user=vastbase database=p
ostgres host=VM-16-10-centos port=58128
```

## 2.安装维护
### 2.1 数据库插件拓展
*   流计算数据库产品 pipelineDB *
*   推荐数据库产品 recDB
*   时序数据库 timescaleDB *
*   分布式数据库插件 citus *
*   列存储插件 IMCS, cstore等
*   面向OLAP的codegen数据库 pg_LLVM
*   向量计算插件 vops
*   数据库性能分析 pg_stat_statements pg_buffercache
*   直接访问数据库文件系统 adminpack
*   加密数据 pgcrypto
*   预热缓存 pg_prewarm
*   检查存储，特别是表膨胀 pgstattuple
*   模糊搜索 pg_trgm*
*   连接到远程服务器 postgres_fdw
*   k近邻（KNN）搜索 btree_gist

### 2.2 pg_stat_statements 数据库统计信息
1.pg_stat_statements 扩展
*   安装
```
yum install postgresql10-contrib.x86_64
```
*   修改配置参数
```
vi $PGDATA/postgresql.conf  

shared_preload_libraries='pg_stat_statements'  # 加载模块　需要重启 , 近期测试不需要添加也可以。自带扩展

track_io_timing = on  # 跟踪IO耗时 (可选)

track_activity_query_size = 2048 # 设置单条SQL的最长长度，超过被截断显示（可选)

pg_stat_statements.max = 10000  #在pg_stat_statements中最多保留多少条统计信息，通过LRU算法，覆盖老的记录。

pg_stat_statements.track = all  # all - (所有SQL包括函数内嵌套的SQL), top - 直接执行的SQL(函数内的sql不被跟踪), none - (不跟踪)

pg_stat_statements.track_utility = off  #是否跟踪非DML语句 (例如DDL，DCL)，on表示跟踪, off表示不跟踪 

pg_stat_statements.save = on #重启后是否保留统计信息  
```

*   重启数据库
```
systemctl restart postgresql-10
```

*   创建扩展
```
create extension pg_stat_statements;

\d pg_stat_statements
                    View "public.pg_stat_statements"
       Column        |       Type       | Collation | Nullable | Description 
---------------------+------------------+-----------+----------+---------
 userid              | oid              |           |          | 执行该语句的用户的 OID
 dbid                | oid              |           |          | 在其中执行该语句的数据库的 OID
 queryid             | bigint           |           |          | 内部哈希码，从语句的解析树计算得来 
 query               | text             |           |          | 语句的文本形式 
 calls               | bigint           |           |          | 被执行的次数 
 total_time          | double precision |           |          | 在该语句中花费的总时间，以毫秒计 
 min_time            | double precision |           |          | 在该语句中花费的最小时间，以毫秒计 
 max_time            | double precision |           |          | 在该语句中花费的最大时间，以毫秒计
 mean_time           | double precision |           |          | 在该语句中花费的平均时间，以毫秒计 
 stddev_time         | double precision |           |          | 在该语句中花费时间的总体标准偏差，以毫秒计 
 rows                | bigint           |           |          | 该语句检索或影响的行总数 
 shared_blks_hit     | bigint           |           |          | 该语句造成的共享块缓冲命中总数 
 shared_blks_read    | bigint           |           |          | 该语句读取的共享块的总数 
 shared_blks_dirtied | bigint           |           |          | 该语句弄脏的共享块的总数 
 shared_blks_written | bigint           |           |          | 
 local_blks_hit      | bigint           |           |          | 
 local_blks_read     | bigint           |           |          | 该语句读取的本地块的总数 
 local_blks_dirtied  | bigint           |           |          | 该语句弄脏的本地块的总数 
 local_blks_written  | bigint           |           |          | 该语句写入的本地块的总数 
 temp_blks_read      | bigint           |           |          | 
 temp_blks_written   | bigint           |           |          | 
 blk_read_time       | double precision |           |          | 该语句花在读取块上的总时间，以毫秒计（如果track_io_timing被启用，否则为零) 
 blk_write_time      | double precision |           |          | 该语句花在写入块上的总时间，以毫秒计（如果track_io_timing被启用，否则为零) 
```
在数据库中生成了一个名为 pg_stat_statements 的视图,对数据库的跟踪也是基于这个视图展开。
分析TOP SQL
最耗IO SQL

*   单次调用最耗IO SQL TOP 5
```
select userid::regrole, dbid, query from pg_stat_statements order by (blk_read_time+blk_write_time)/calls desc limit 5;  
```
*   总最耗IO SQL TOP 5
```
select userid::regrole, dbid, query from pg_stat_statements order by (blk_read_time+blk_write_time) desc limit 5;  
```
最耗时 SQL
*   单次调用最耗时 SQL TOP 5
```
select userid::regrole, dbid, query from pg_stat_statements order by mean_time desc limit 5;  

```
*   总最耗时 SQL TOP 5
```
select userid::regrole, dbid, query from pg_stat_statements order by total_time desc limit 5;  
```
*   响应时间抖动最严重 SQL
```
select userid::regrole, dbid, query from pg_stat_statements order by stddev_time desc limit 5;  
```
*   最耗共享内存 SQL
```
select userid::regrole, dbid, query from pg_stat_statements order by (shared_blks_hit+shared_blks_dirtied) desc limit 5;  
```
*   最耗临时空间 SQL
```
select userid::regrole, dbid, query from pg_stat_statements order by temp_blks_written desc limit 5;  
```

*   最访问频繁 SQL
```
select userid::regrole, dbid, query ,calls from pg_stat_statements order by calls desc limit 5;
```
* 慢SQL
```
SELECT
        query,
        calls,
        total_time,
        (total_time / calls) AS average ,
        ROWS,
        100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read,
        0) AS hit_percent
FROM
        pg_stat_statements
ORDER BY
        average DESC
LIMIT 10;
```
重置统计信息
pg_stat_statements是累积的统计，如果要查看某个时间段的统计，需要打快照
```
建快照表
create table stat_pg_stat_statements as select now() ,* from pg_stat_statements where 1=2;
插入数据
insert into stat_pg_stat_statements select now() ,* from pg_stat_statements;
```
用户也可以定期清理历史的统计信息，通过调用如下SQL

```
select pg_stat_statements_reset();  
```


### 2.3 auto_explain 模块
auto_explain模块提供了一种方法，可以自动记录慢语句的执行计划，而不必手动运行EXPLAIN。这对于跟踪大型应用程序中未优化的查询特别有用。
配置参数：
通常情况下，这些参数是在postgresql.conf中设置的：
```
# postgresql.conf
session_preload_libraries = 'auto_explain'

auto_explain.log_min_duration = '3s'
```
Here is a full list of the auto_explain parameters, and their defaults:
```
Parameter                                PostgreSQL defaults                 ScaleGrid defaults
auto_explain.log_min_duration                 -1                                   100
auto_explain.log_analyze                      Off                                  On
auto_explain.log_timing                       On (with log_analyze)                On
auto_explain.log_buffers                      Off                                  On
auto_explain.log_verbose                      Off                                  On
auto_explain.log_triggers                     Off                                  Off
auto_explain.log_nested_statements            Off                                  Off
auto_explain.log_settings (v12)               Off                                  Off
auto_explain.log_wal (v13)                    Off                                  Off
auto_explain.log_format                       TEXT                                 JSON
auto_explain.log_level                        LOG                                  LOG
auto_explain.sample_rate                      1                                     1
```
### 2.4 PG 慢日志分析工具pgbadger
1.安装依赖
```
yum install perl-ExtUtils-CBuilder perl-ExtUtils-MakeMaker
```
*   下载地址：https://github.com/darold/pgbadger/releases
```
perl Makefile.PL
make
make install
```

*   pgbader --help使用说明：https://github.com/darold/pgbadger
*   使用shell截断日志: https://blog.garage-coding.com/2016/07/16/analyzing-postgres-logs-with-pgbadger.html
*   pgbader使用截图样例：https://severalnines.com/blog/postgresql-log-analysis-pgbadger
*   配置日志格式前提
```
log_destination = 'stderr'
# 日志记录类型，默认是stderr，只记录错误输出
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,client=%h '
# log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_checkpoints = on
# 系统一天之类发生了多少次checkpoint，以及每次checkpoint的一些详细信息，频繁的checkpoint影响系统性能
log_connections = on
# log_connections    --用户session登陆时是否写入日志，默认off
log_disconnections = on
# 用户session退出时是否写入日志，默认off
log_lock_waits = on
# 一天内有多少个超过死锁时间的锁发生，默认是off，可以设置开启。这个可以区分SQL慢是资源紧张还是锁等待的问题
log_temp_files = 0
log_autovacuum_min_duration = 0
log_error_verbosity = default
log_statement = off
lc_messages='C'
Log_min_duration_statement = 1000
# 单位ms，超过1s为慢查询
# 其他日志
logging_collector      --是否开启日志收集开关，默认off，开启要重启DB
log_directory      --日志路径，默认是$PGDATA/pg_log
log_filename       --日志名称，默认是postgresql-%Y-%m-%d_%H%M%S.log
log_rotation_age   --保留单个文件的最大时长,默认是1d,也有1h,1min,1s,个人觉得不实用
log_rotation_size  --保留单个文件的最大尺寸，默认是10MB
pg_statement  = log_statement
```
参数值是none，即不记录，可以设置ddl(记录create,drop和alter)、mod(记录ddl+insert,delete,update和truncate)和all(mod+select)

*   使用pg_ctl reload参数log_line_prefix可能不会生效，在psql下直接更改
```
alter system set log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,client=%h ';
```
生成html格式
```
pgbadger --prefix='%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h ' postgresql-5.log -f stderr
```

*   生成csv格式导入数据库：https://blog.csdn.net/shanzhizi/article/details/47616645
*   自动分析慢日志：https://blog.csdn.net/ctypyb2002/article/details/80733465
```
SELECT pg_reload_conf();
```
*   分析脚本
```
#!/bin/bash
set -euo pipefail

#==============================================================#
# File      :   pg-report
# Ctime     :   2021-09-17
# Mtime     :   2021-09-17
# Desc      :   Generate pgbadger HTML report to /pg/stat/logs
# Path      :   /pg/bin/pg-badger
# Depend    :   pgbadger, /pg/stat
# Author    :   Vonng(fengruohang@outlook.com)
# Copyright (C) 2018-2021 Ruohang Feng
#==============================================================#

# usage
# pg-report       incremental report for today's log
# pg-report full  full report for all historic log

# run as postgres
if [[ "$(whoami)" != "postgres" ]]; then
	echo "run this as dbsu postgres"
	exit 1
fi
mkdir -p /pg/stat/logs

MODE=${1-''}

if [[ ${MODE} == "full" ]]; then
	pgbadger \
	   -I /pg/data/log/*.csv \
	   -f csv \
	   --outdir /pg/stat/logs \
	   --wide-char \
	   --average 1 \
	   --sample 3
else
    LATEST_LOGS="$(find /pg/data/log -name '*.csv' -mtime 0)"
	pgbadger \
	   -I ${LATEST_LOGS} \
	   -f csv \
	   --outdir /pg/stat/logs \
	   --wide-char \
	   --average 1 \
	   --sample 3
fi
```
*   参考文档：
https://www.modb.pro/db/42051
https://github.com/darold/pgbadger/releases
https://pgbadger.darold.net/#about

### 2.5 pg_freespacemap 什么时候用vacuum full
When should I do VACUUM FULL?Posted on Dec 30, 2016#postgres
There is unfortunately no best practice when you should execute “VACUUM FULL”. The extension pg_freespacemap however gives you suggestion.
The following query shows the average freespace ratio of the table you want to know.
```
testdb=# CREATE EXTENSION pg_freespacemap;CREATE EXTENSION

testdb=# SELECT count(*) as "number of pages",
pg_size_pretty(cast(avg(avail) as bigint)) as "Av. freespace size",
round(100 * avg(avail)/8192 ,2) as "Av. freespace ratio"
FROM pg_freespace('pgbench_accounts');
number of pages | Av. freespace size | Av. freespace ratio
-----------------+--------------------+---------------------
1640 | 99 bytes | 1.21
(1 row)
```
As the result above, You can find that there are few free spaces.
If you delete almost tuples and execute VACUUM command, you can find that almost pages are spaces ones.
```
testdb=# DELETE FROM pgbench_accounts WHERE aid %10 != 0 OR aid < 100;DELETE 90009

testdb=# VACUUM pgbench_accounts;
VACUUM

testdb=# SELECT count(*) as "number of pages",
pg_size_pretty(cast(avg(avail) as bigint)) as "Av. freespace size",
round(100 * avg(avail)/8192 ,2) as "Av. freespace ratio"
FROM pg_freespace('pgbench_accounts');
number of pages | Av. freespace size | Av. freespace ratio
-----------------+--------------------+---------------------
1640 | 7124 bytes | 86.97
(1 row)
```
The following query inspects the freespace ratio of each page of the specified table.
```
testdb=# SELECT *, round(100 * avail/8192 ,2) as "freespace ratio"
FROM pg_freespace('pgbench_accounts');
blkno | avail | freespace ratio
-------+-------+-----------------
0 | 7904 | 96.00
1 | 7520 | 91.00
2 | 7136 | 87.00
3 | 7136 | 87.00
4 | 7136 | 87.00
5 | 7136 | 87.00
```
After executing VACUUM FULL, you can find that the table file of pgbench_accounts has been compacted.

```
testdb=# VACUUM FULL pgbench_accounts;
VACUUM

testdb=# SELECT count(*) as "number of pages",
pg_size_pretty(cast(avg(avail) as bigint)) as "Av. freespace size",
round(100 * avg(avail)/8192 ,2) as "Av. freespace ratio"
FROM pg_freespace('pgbench_accounts');
number of pages | Av. freespace size | Av. freespace ratio
-----------------+--------------------+---------------------
164 | 0 bytes | 0.00
(1 row)
```


## 3.服务器管理


## 4.SQL
### 4.1 CREATE
* 创建默认分区
```
CREATE TABLE part_table PARTITION OF father_table DEFAULT;
```
* 物化视图
```
CREATE MATERIALIZED VIEW mymatview AS SELECT * FROM t;
```
### 4.2 select 
* 查看有哪些扩展
```
select * from pg_available_extensions;
\dx
```
* 查看数据库大小
```
select pg_database.datname,pg_size_pretty(pg_database_size(pg_database.datname)) AS size  
from pg_database;
```
* 查看所有schema里表大小，按从大到小排列
```
select relname, pg_size_pretty(pg_relation_size(relid))  
from pg_stat_user_tables
where schemaname =  'schemaname' order by pg_relation_size(relid) desc;
```
* 查看所有schema里索引大小，按从大到小排列
```
select indexrelname,pg_size_pretty( pg_relation_size(relid))   
from pg_stat_user_indexes
where schemaname =  'schemaname' order by pg_relation_size(relid) desc;
```
* 数据库年龄
```
select datname,age(datfrozenxid),2^31-age(datfrozenxid) age_remain from pg_database order by age(datfrozenxid) desc;
```
* 表年龄
```
SELECT
    current_database (),
    rolname,
    nspname,
    relkind,
    relname,
    age(relfrozenxid),
    2 ^ 31 - age(relfrozenxid) age_remain
FROM
    pg_authid t1
JOIN pg_class t2 ON t1.oid = t2.relowner
JOIN pg_namespace t3 ON t2.relnamespace = t3.oid
WHERE
    t2.relkind IN ($$t$$, $$r$$)
ORDER BY
    age(relfrozenxid) DESC
LIMIT 5;
```
* 正在运行的最老快照的年龄
```
SELECT now() -
CASE
WHEN backend_xid IS NOT NULL
THEN xact_start
ELSE query_start END
AS age
, pid
, backend_xid AS xid
, backend_xmin AS xmin
, state
FROM pg_stat_activity
WHERE backend_type = 'client backend'
ORDER BY 1 DESC;
```
* 查看是否做过统计信息收集
```
select * from pg_stat_user_tables where relname='amlcalfactor';
last_vacuum        无        上次手动vacuum的时间
last_autovacuum        无        上次autovacuum的时间
last_analyze        无        上次analyze的时间
last_autoanalyze        2019/4/9 14:12        上次自动analyze的时间
vacuum_count        0        vacuum的次数
autovacuum_count        0        autovacuum的次数
analyze_count        0        analyze的次数
autoanalyze_count        1        自动analyze的次数
```
* 查询Xlog(10以下版本)
```
select pg_current_xlog_location(),
                  pg_xlogfile_name(pg_current_xlog_location()),
                  pg_xlogfile_name_offset(pg_current_xlog_location());
```
* 查看schema大小
``` 
SELECT schema_name,
    pg_size_pretty(sum(table_size)::bigint) as "disk space",
    round((sum(table_size) / pg_database_size(current_database())) * 100,2)
        as "percent(%)"
FROM (
     SELECT pg_catalog.pg_namespace.nspname as schema_name,
         pg_total_relation_size(pg_catalog.pg_class.oid) as table_size
     FROM   pg_catalog.pg_class
         JOIN pg_catalog.pg_namespace
             ON relnamespace = pg_catalog.pg_namespace.oid
) t
GROUP BY schema_name
ORDER BY "percent(%)" desc;
```

* 查看权限
```
查看某用户的系统权限
SELECT * FROM  pg_roles WHERE rolname='postgres';
查看某用户的表权限
select * from information_schema.table_privileges where grantee='postgres';
查看某用户的usage权限
select * from information_schema.usage_privileges where grantee='postgres';
查看某用户在存储过程函数的执行权限
select * from information_schema.routine_privileges where grantee='postgres';
查看某用户在某表的列上的权限
select * from information_schema.column_privileges where grantee='postgres';
查看当前用户能够访问的数据类型
select * from information_schema.data_type_privileges ;
查看用户自定义类型上授予的USAGE权限
select * from information_schema.udt_privileges where grantee='postgres';
```
### 4.3 GRANT
* 给用户某个数据库权限
```
grant all on database database_name to user_name;
```

### 4.4 ALTER
* 设置用户永久有效
```
alter user user_name with valid until 'infinity';
```
* 解除触发器
```
alter table table enable trigger all;
```

### 4.5 常用SQL
* kill
```
SELECT pg_cancel_backend(PID);
这种方式只能kill select查询，对update、delete 及DML不生效)

第二种是：
SELECT pg_terminate_backend(PID);
这种可以kill掉各种操作(select、update、delete、drop等)操作
```
* 清楚所有连接
```
clean connection to all force for database cicgroup;
```
*	手动触发归档
```
pg10.0之前：
select pg_switch_xlog();
pg10.0之后：
select pg_switch_wal();
```
* 缓存命中率(正常非常接近1 否则应该调整shared_buffers的配置 低于99% 可以适当调大)
```
select blks_hit::float/(blks_read+blks_hit) as cache_hit_ratio from pg_stat_database where datname=current_database();
```
* 事务提交率(正常等于或者接近1 否则检查是否太多死锁和超时)
```
select xact_commit::float/(xact_commit+xact_rollback) as successful_xact_ratio from pg_stat_database where datname=current_database();
```
* 查询平均执行时间最长的SQL
```
select total_time / calls as avgtime, query,calls,rows
total_time,min_time,max_time,mean_time,stddev_time,
shared_blks_hit,shared_blks_read
from pg_stat_statements order by avgtime DESC limit 10 ;
```
* pg_stat_statements_reset 重置
```
select pg_stat_statements_reset();
```


* 数据库表大小统计
```
with data as (
  select
    c.oid,
    (select spcname from pg_tablespace where oid = reltablespace) as tblspace,
    nspname as schema_name,
    relname as table_name,
    c.reltuples as row_estimate,
    pg_total_relation_size(c.oid) as total_bytes,
    pg_indexes_size(c.oid) as index_bytes,
    pg_total_relation_size(reltoastrelid) as toast_bytes,
    pg_total_relation_size(c.oid) - pg_indexes_size(c.oid) - coalesce(pg_total_relation_size(reltoastrelid), 0) as table_bytes
  from pg_class c
  left join pg_namespace n on n.oid = c.relnamespace
  where relkind = 'r' and nspname <> 'pg_catalog'
), data2 as (
  select
    null::oid as oid,
    null as tblspace,
    null as schema_name,
    '*** TOTAL ***' as table_name,
    sum(row_estimate) as row_estimate,
    sum(total_bytes) as total_bytes,
    sum(index_bytes) as index_bytes,
    sum(toast_bytes) as toast_bytes,
    sum(table_bytes) as table_bytes
  from data
  union all
  select
    null::oid as oid,
    null,
    null as schema_name,
    '    tablespace: [' || coalesce(tblspace, 'pg_default') || ']' as table_name,
    sum(row_estimate) as row_estimate,
    sum(total_bytes) as total_bytes,
    sum(index_bytes) as index_bytes,
    sum(toast_bytes) as toast_bytes,
    sum(table_bytes) as table_bytes
  from data
  where (select count(distinct coalesce(tblspace, 'pg_default')) from data) > 1 -- don't show this part if there are no custom tablespaces
  group by tblspace
  union all
  select null::oid, null, null, null, null, null, null, null, null
  union all
  select * from data
)
select
  coalesce(nullif(schema_name, 'public') || '.', '') || table_name || coalesce(' [' || tblspace || ']', '') as "Table",
  '~' || case
    when row_estimate > 10^12 then round(row_estimate::numeric / 10^12::numeric, 0)::text || 'T'
    when row_estimate > 10^9 then round(row_estimate::numeric / 10^9::numeric, 0)::text || 'B'
    when row_estimate > 10^6 then round(row_estimate::numeric / 10^6::numeric, 0)::text || 'M'
    when row_estimate > 10^3 then round(row_estimate::numeric / 10^3::numeric, 0)::text || 'k'
    else row_estimate::text
  end as "Rows",
  pg_size_pretty(total_bytes) || ' (' || round(
    100 * total_bytes::numeric / nullif(sum(total_bytes) over (partition by (schema_name is null), left(table_name, 3) = '***'), 0),
    2
  )::text || '%)' as "Total Size",
  pg_size_pretty(table_bytes) || ' (' || round(
    100 * table_bytes::numeric / nullif(sum(table_bytes) over (partition by (schema_name is null), left(table_name, 3) = '***'), 0),
    2
  )::text || '%)' as "Table Size",
  pg_size_pretty(index_bytes) || ' (' || round(
    100 * index_bytes::numeric / nullif(sum(index_bytes) over (partition by (schema_name is null), left(table_name, 3) = '***'), 0),
    2
  )::text || '%)' as "Index(es) Size",
  pg_size_pretty(toast_bytes) || ' (' || round(
    100 * toast_bytes::numeric / nullif(sum(toast_bytes) over (partition by (schema_name is null), left(table_name, 3) = '***'), 0),
    2
  )::text || '%)' as "TOAST Size"
from data2
where schema_name is distinct from 'information_schema'
order by oid is null desc, total_bytes desc nulls last;
```

* 表膨胀检查
```
SELECT    
  current_database() AS db, schemaname, tablename, reltuples::bigint AS tups, relpages::bigint AS pages, otta,    
  ROUND(CASE WHEN otta=0 OR sml.relpages=0 OR sml.relpages=otta THEN 0.0 ELSE sml.relpages/otta::numeric END,1) AS tbloat,    
  CASE WHEN relpages < otta THEN 0 ELSE relpages::bigint - otta END AS wastedpages,    
  CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::bigint END AS wastedbytes,    
  CASE WHEN relpages < otta THEN $$0 bytes$$::text ELSE (bs*(relpages-otta))::bigint || $$ bytes$$ END AS wastedsize,    
  iname, ituples::bigint AS itups, ipages::bigint AS ipages, iotta,    
  ROUND(CASE WHEN iotta=0 OR ipages=0 OR ipages=iotta THEN 0.0 ELSE ipages/iotta::numeric END,1) AS ibloat,    
  CASE WHEN ipages < iotta THEN 0 ELSE ipages::bigint - iotta END AS wastedipages,    
  CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) END AS wastedibytes,    
  CASE WHEN ipages < iotta THEN $$0 bytes$$ ELSE (bs*(ipages-iotta))::bigint || $$ bytes$$ END AS wastedisize,    
  CASE WHEN relpages < otta THEN    
    CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta::bigint) END    
    ELSE CASE WHEN ipages < iotta THEN bs*(relpages-otta::bigint)    
      ELSE bs*(relpages-otta::bigint + ipages-iotta::bigint) END    
  END AS totalwastedbytes    
FROM (    
  SELECT    
    nn.nspname AS schemaname,    
    cc.relname AS tablename,    
    COALESCE(cc.reltuples,0) AS reltuples,    
    COALESCE(cc.relpages,0) AS relpages,    
    COALESCE(bs,0) AS bs,    
    COALESCE(CEIL((cc.reltuples*((datahdr+ma-    
      (CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END))+nullhdr2+4))/(bs-20::float)),0) AS otta,    
    COALESCE(c2.relname,$$?$$) AS iname, COALESCE(c2.reltuples,0) AS ituples, COALESCE(c2.relpages,0) AS ipages,    
    COALESCE(CEIL((c2.reltuples*(datahdr-12))/(bs-20::float)),0) AS iotta -- very rough approximation, assumes all cols    
  FROM    
     pg_class cc    
  JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname <> $$information_schema$$    
  LEFT JOIN    
  (    
    SELECT    
      ma,bs,foo.nspname,foo.relname,    
      (datawidth+(hdr+ma-(case when hdr%ma=0 THEN ma ELSE hdr%ma END)))::numeric AS datahdr,    
      (maxfracsum*(nullhdr+ma-(case when nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2    
    FROM (    
      SELECT    
        ns.nspname, tbl.relname, hdr, ma, bs,    
        SUM((1-coalesce(null_frac,0))*coalesce(avg_width, 2048)) AS datawidth,    
        MAX(coalesce(null_frac,0)) AS maxfracsum,    
        hdr+(    
          SELECT 1+count(*)/8    
          FROM pg_stats s2    
          WHERE null_frac<>0 AND s2.schemaname = ns.nspname AND s2.tablename = tbl.relname    
        ) AS nullhdr    
      FROM pg_attribute att     
      JOIN pg_class tbl ON att.attrelid = tbl.oid    
      JOIN pg_namespace ns ON ns.oid = tbl.relnamespace     
      LEFT JOIN pg_stats s ON s.schemaname=ns.nspname    
      AND s.tablename = tbl.relname    
      AND s.inherited=false    
      AND s.attname=att.attname,    
      (    
        SELECT    
          (SELECT current_setting($$block_size$$)::numeric) AS bs,    
            CASE WHEN SUBSTRING(SPLIT_PART(v, $$ $$, 2) FROM $$#"[0-9]+.[0-9]+#"%$$ for $$#$$)    
              IN ($$8.0$$,$$8.1$$,$$8.2$$) THEN 27 ELSE 23 END AS hdr,    
          CASE WHEN v ~ $$mingw32$$ OR v ~ $$64-bit$$ THEN 8 ELSE 4 END AS ma    
        FROM (SELECT version() AS v) AS foo    
      ) AS constants    
      WHERE att.attnum > 0 AND tbl.relkind=$$r$$    
      GROUP BY 1,2,3,4,5    
    ) AS foo    
  ) AS rs    
  ON cc.relname = rs.relname AND nn.nspname = rs.nspname    
  LEFT JOIN pg_index i ON indrelid = cc.oid    
  LEFT JOIN pg_class c2 ON c2.oid = i.indexrelid    
) AS sml order by wastedbytes desc limit 5   ;
```

* 查看数据库所有配置
```
with icp (name) as (
  values ('listen_addresses'), ('max_connections'), ('superuser_reserved_connections'), ('shared_buffers')
       , ('work_mem'), ('maintenance_work_mem'), ('shared_preload_libraries'), ('vacuum_cost_delay')
       , ('vacuum_cost_page_hit'), ('vacuum_cost_page_miss'), ('vacuum_cost_page_dirty'), ('vacuum_cost_limit')
       , ('bgwriter_delay'), ('bgwriter_lru_maxpages'), ('bgwriter_lru_multiplier'), ('effective_io_concurrency')
       , ('max_worker_processes'), ('wal_level'), ('synchronous_commit'), ('checkpoint_timeout')
       , ('min_wal_size'), ('max_wal_size'), ('checkpoint_completion_target'), ('max_wal_senders')
       , ('hot_standby'), ('max_standby_streaming_delay'), ('hot_standby_feedback'), ('effective_cache_size')
       , ('log_directory'), ('log_filename'), ('log_min_duration_statement'), ('log_checkpoints')
       , ('log_line_prefix'), ('log_lock_waits'), ('log_replication_commands'), ('log_temp_files')
       , ('track_io_timing'), ('track_functions'), ('track_activity_query_size'), ('log_autovacuum_min_duration')
       , ('autovacuum_max_workers'), ('autovacuum_naptime'), ('autovacuum_vacuum_threshold')
       , ('autovacuum_analyze_threshold'), ('autovacuum_vacuum_scale_factor'), ('autovacuum_analyze_scale_factor')
       , ('autovacuum_vacuum_cost_delay'), ('vacuum_freeze_min_age'), ('vacuum_freeze_table_age')
       , ('pg_stat_statements.max'), ('pg_stat_statements.track')
       , ('pg_stat_statements.track_utility'), ('pg_stat_statements.save')
)
select rpad (case when source in ('default', 'override') then '(*) ' else '    ' end ||
             rpad (name, 35) ||
             case when setting != reset_val then ' (c)' else '' end ||
             case when pending_restart then ' !!!' else '' end
            , 47) as name
     , rpad (case when (unit = '8kB' and setting != '-1') then pg_size_pretty (setting::bigint * 8192)
                  when (unit = 'kB' and  setting != '-1') then pg_size_pretty (setting::bigint * 1024)
                  else setting end, 25) as setting
     , rpad (case when unit in ('8kB', 'kB') then 'byte' else unit end, 4) as unit
     , rpad (case when (unit = '8kB' and reset_val != '-1') then pg_size_pretty (reset_val::bigint * 8192)
                  when (unit = 'kB' and  reset_val != '-1') then pg_size_pretty (reset_val::bigint * 1024)
                  else reset_val end, 25) as reset_val
     , rpad (case when (unit = '8kB' and boot_val != '-1') then pg_size_pretty (boot_val::bigint * 8192)
                  when (unit = 'kB' and  boot_val != '-1') then pg_size_pretty (boot_val::bigint * 1024)
                  else boot_val end, 25) as boot_val
     , rpad (case source
               when 'environment variable' then 'env'
               when 'configuration file' then '.conf'
               when 'configuration file' then '.conf'
               else source
             end
            , 13) as source
     --, sourcefile
  from pg_settings
where (sourcefile is not null
    or pending_restart
    or setting != boot_val
    or reset_val != boot_val
    or exists (select 1 from icp where icp.name = pg_settings.name)
    or source not in ('default', 'override'))
   and (name, setting) not in ( ('log_filename', 'postgresql-%Y-%m-%d.log')
                              , ('log_checkpoints', 'on')
                              , ('logging_collector', 'on')
                              , ('log_line_prefix', '%m %p %u@%d from %h [vxid:%v txid:%x] [%i] ')
                              , ('log_replication_commands', 'on')
                              , ('log_destination', 'stderr')
                              , ('log_file_mode', '0600')
                              , ('unix_socket_permissions', '0777')
                              , ('transaction_read_only', 'on')
                              , ('transaction_read_only', 'off')
                              , ('application_name', 'psql')
                              , ('archive_command', '(disabled)')
                              )
order by category, name;
```
* 所有表vacuum状态
```
WITH table_opts AS
  (SELECT pg_class.oid,
          relname,
          nspname,
          array_to_string(reloptions, '') AS relopts
    FROM pg_class
   INNER JOIN pg_namespace ns ON relnamespace = ns.oid),
     vacuum_settings AS
   (SELECT oid,
           relname,
           nspname,
           CASE
               WHEN relopts LIKE '%autovacuum_vacuum_threshold%' THEN regexp_replace(relopts, '.*autovacuum_vacuum_threshold=([0-9.]+).*', E'\\\\\\1')::integer
               ELSE current_setting('autovacuum_vacuum_threshold')::integer
           END AS autovacuum_vacuum_threshold,
           CASE
               WHEN relopts LIKE '%autovacuum_vacuum_scale_factor%' THEN regexp_replace(relopts, '.*autovacuum_vacuum_scale_factor=([0-9.]+).*', E'\\\\\\1')::real
               ELSE current_setting('autovacuum_vacuum_scale_factor')::real
           END AS autovacuum_vacuum_scale_factor
    FROM table_opts)
  SELECT vacuum_settings.nspname AS SCHEMA,
         vacuum_settings.relname AS TABLE,
         to_char(psut.last_vacuum, 'YYYY-MM-DD HH24:MI') AS last_vacuum,
         to_char(psut.last_autovacuum, 'YYYY-MM-DD HH24:MI') AS last_autovacuum,
         to_char(pg_class.reltuples, '9G999G999G999') AS rowcount,
         to_char(psut.n_dead_tup, '9G999G999G999') AS dead_rowcount,
         to_char(autovacuum_vacuum_threshold + (autovacuum_vacuum_scale_factor::numeric * pg_class.reltuples), '9G999G999G999') AS autovacuum_threshold,
         CASE
             WHEN autovacuum_vacuum_threshold + (autovacuum_vacuum_scale_factor::numeric * pg_class.reltuples) < psut.n_dead_tup THEN 'yes'
         END AS expect_autovacuum
  FROM pg_stat_user_tables psut
  INNER JOIN pg_class ON psut.relid = pg_class.oid
  INNER JOIN vacuum_settings ON pg_class.oid = vacuum_settings.oid
  ORDER BY 1,
           2;
```

* 数据库大小统计
```
with data as (
  select
    d.oid,
    (select spcname from pg_tablespace where oid = dattablespace) as tblspace,
    d.datname as database_name,
    pg_catalog.pg_get_userbyid(d.datdba) as owner,
    has_database_privilege(d.datname, 'connect') as has_access,
    pg_database_size(d.datname) as size,
    stats_reset,
    blks_hit,
    blks_read,
    xact_commit,
    xact_rollback,
    conflicts,
    deadlocks,
    temp_files,
    temp_bytes
  from pg_catalog.pg_database d
  join pg_stat_database s on s.datid = d.oid
), data2 as (
  select
    null::oid as oid,
    null as tblspace,
    '*** TOTAL ***' as database_name,
    null as owner,
    true as has_access,
    sum(size) as size,
    null::timestamptz as stats_reset,
    sum(blks_hit) as blks_hit,
    sum(blks_read) as blks_read,
    sum(xact_commit) as xact_commit,
    sum(xact_rollback) as xact_rollback,
    sum(conflicts) as conflicts,
    sum(deadlocks) as deadlocks,
    sum(temp_files) as temp_files,
    sum(temp_bytes) as temp_bytes
  from data
  union all
  select null::oid, null, null, null, true, null, null, null, null, null, null, null, null, null, null
  union all
  select
    oid,
    tblspace,
    database_name,
    owner,
    has_access,
    size,
    stats_reset,
    blks_hit,
    blks_read,
    xact_commit,
    xact_rollback,
    conflicts,
    deadlocks,
    temp_files,
    temp_bytes
  from data
)
select
  database_name || coalesce(' [' || nullif(tblspace, 'pg_default') || ']', '') as "Database",
  case
    when has_access then
      pg_size_pretty(size) || ' (' || round(
        100 * size::numeric / nullif(sum(size) over (partition by (oid is null)), 0),
        2
      )::text || '%)'
    else 'no access'
  end as "Size",
  (now() - stats_reset)::interval(0)::text as "Stats Age",
  case
    when blks_hit + blks_read > 0 then
      (round(blks_hit * 100::numeric / (blks_hit + blks_read), 2))::text || '%'
    else null
  end as "Cache eff.",
  case
    when xact_commit + xact_rollback > 0 then
      (round(xact_commit * 100::numeric / (xact_commit + xact_rollback), 2))::text || '%'
    else null
  end as "Committed",
  conflicts as "Conflicts",
  deadlocks as "Deadlocks",
  temp_files::text || coalesce(' (' || pg_size_pretty(temp_bytes) || ')', '') as "Temp. Files"
from data2
order by oid is null desc, size desc nulls last;
```

* 查看当前事务锁等待、持锁信息的SQL
```
with    
t_wait as    
(    
  select a.mode,a.locktype,a.database,a.relation,a.page,a.tuple,a.classid,a.granted,   
  a.objid,a.objsubid,a.pid,a.virtualtransaction,a.virtualxid,a.transactionid,a.fastpath,    
  b.state,b.query,b.xact_start,b.query_start,b.usename,b.datname,b.client_addr,b.client_port,b.application_name   
    from pg_locks a,pg_stat_activity b where a.pid=b.pid and not a.granted   
),   
t_run as   
(   
  select a.mode,a.locktype,a.database,a.relation,a.page,a.tuple,a.classid,a.granted,   
  a.objid,a.objsubid,a.pid,a.virtualtransaction,a.virtualxid,a.transactionid,a.fastpath,   
  b.state,b.query,b.xact_start,b.query_start,b.usename,b.datname,b.client_addr,b.client_port,b.application_name   
    from pg_locks a,pg_stat_activity b where a.pid=b.pid and a.granted   
),   
t_overlap as   
(   
  select r.* from t_wait w join t_run r on   
  (   
    r.locktype is not distinct from w.locktype and   
    r.database is not distinct from w.database and   
    r.relation is not distinct from w.relation and   
    r.page is not distinct from w.page and   
    r.tuple is not distinct from w.tuple and   
    r.virtualxid is not distinct from w.virtualxid and   
    r.transactionid is not distinct from w.transactionid and   
    r.classid is not distinct from w.classid and   
    r.objid is not distinct from w.objid and   
    r.objsubid is not distinct from w.objsubid and   
    r.pid <> w.pid   
  )    
),    
t_unionall as    
(    
  select r.* from t_overlap r    
  union all    
  select w.* from t_wait w    
)    
select locktype,datname,relation::regclass,page,tuple,virtualxid,transactionid::text,classid::regclass,objid,objsubid,   
string_agg(   
'Pid: '||case when pid is null then 'NULL' else pid::text end||chr(10)||   
'Lock_Granted: '||case when granted is null then 'NULL' else granted::text end||' , Mode: '||case when mode is null then 'NULL' else mode::text end||' , FastPath: '||case when fastpath is null then 'NULL' else fastpath::text end||' , VirtualTransaction: '||case when virtualtransaction is null then 'NULL' else virtualtransaction::text end||' , Session_State: '||case when state is null then 'NULL' else state::text end||chr(10)||   
'Username: '||case when usename is null then 'NULL' else usename::text end||' , Database: '||case when datname is null then 'NULL' else datname::text end||' , Client_Addr: '||case when client_addr is null then 'NULL' else client_addr::text end||' , Client_Port: '||case when client_port is null then 'NULL' else client_port::text end||' , Application_Name: '||case when application_name is null then 'NULL' else application_name::text end||chr(10)||    
'Xact_Start: '||case when xact_start is null then 'NULL' else xact_start::text end||' , Query_Start: '||case when query_start is null then 'NULL' else query_start::text end||' , Xact_Elapse: '||case when (now()-xact_start) is null then 'NULL' else (now()-xact_start)::text end||' , Query_Elapse: '||case when (now()-query_start) is null then 'NULL' else (now()-query_start)::text end||chr(10)||    
'SQL (Current SQL in Transaction): '||chr(10)||  
case when query is null then 'NULL' else query::text end,    
chr(10)||'--------'||chr(10)    
order by    
  (  case mode    
    when 'INVALID' then 0   
    when 'AccessShareLock' then 1   
    when 'RowShareLock' then 2   
    when 'RowExclusiveLock' then 3   
    when 'ShareUpdateExclusiveLock' then 4   
    when 'ShareLock' then 5   
    when 'ShareRowExclusiveLock' then 6   
    when 'ExclusiveLock' then 7   
    when 'AccessExclusiveLock' then 8   
    else 0   
  end  ) desc,   
  (case when granted then 0 else 1 end)  
) as lock_conflict  
from t_unionall   
group by   
locktype,datname,relation,page,tuple,virtualxid,transactionid::text,classid,objid,objsubid ;  
```

* 索引膨胀检查
```
SELECT
  current_database() AS db, schemaname, tablename, reltuples::bigint AS tups, relpages::bigint AS pages, otta,
  ROUND(CASE WHEN otta=0 OR sml.relpages=0 OR sml.relpages=otta THEN 0.0 ELSE sml.relpages/otta::numeric END,1) AS tbloat,
  CASE WHEN relpages < otta THEN 0 ELSE relpages::bigint - otta END AS wastedpages,
  CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::bigint END AS wastedbytes,
  CASE WHEN relpages < otta THEN $$0 bytes$$::text ELSE (bs*(relpages-otta))::bigint || $$ bytes$$ END AS wastedsize,
  iname, ituples::bigint AS itups, ipages::bigint AS ipages, iotta,
  ROUND(CASE WHEN iotta=0 OR ipages=0 OR ipages=iotta THEN 0.0 ELSE ipages/iotta::numeric END,1) AS ibloat,
  CASE WHEN ipages < iotta THEN 0 ELSE ipages::bigint - iotta END AS wastedipages,
  CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) END AS wastedibytes,
  CASE WHEN ipages < iotta THEN $$0 bytes$$ ELSE (bs*(ipages-iotta))::bigint || $$ bytes$$ END AS wastedisize,
  CASE WHEN relpages < otta THEN
    CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta::bigint) END
    ELSE CASE WHEN ipages < iotta THEN bs*(relpages-otta::bigint)
      ELSE bs*(relpages-otta::bigint + ipages-iotta::bigint) END
  END AS totalwastedbytes
FROM (
  SELECT
    nn.nspname AS schemaname,
    cc.relname AS tablename,
    COALESCE(cc.reltuples,0) AS reltuples,
    COALESCE(cc.relpages,0) AS relpages,
    COALESCE(bs,0) AS bs,
    COALESCE(CEIL((cc.reltuples*((datahdr+ma-
      (CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END))+nullhdr2+4))/(bs-20::float)),0) AS otta,
    COALESCE(c2.relname,$$?$$) AS iname, COALESCE(c2.reltuples,0) AS ituples, COALESCE(c2.relpages,0) AS ipages,
    COALESCE(CEIL((c2.reltuples*(datahdr-12))/(bs-20::float)),0) AS iotta -- very rough approximation, assumes all cols
  FROM
     pg_class cc
  JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname <> $$information_schema$$
  LEFT JOIN
  (
    SELECT
      ma,bs,foo.nspname,foo.relname,
      (datawidth+(hdr+ma-(case when hdr%ma=0 THEN ma ELSE hdr%ma END)))::numeric AS datahdr,
      (maxfracsum*(nullhdr+ma-(case when nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
    FROM (
      SELECT
        ns.nspname, tbl.relname, hdr, ma, bs,
        SUM((1-coalesce(null_frac,0))*coalesce(avg_width, 2048)) AS datawidth,
        MAX(coalesce(null_frac,0)) AS maxfracsum,
        hdr+(
          SELECT 1+count(*)/8
          FROM pg_stats s2
          WHERE null_frac<>0 AND s2.schemaname = ns.nspname AND s2.tablename = tbl.relname
        ) AS nullhdr
      FROM pg_attribute att
      JOIN pg_class tbl ON att.attrelid = tbl.oid
      JOIN pg_namespace ns ON ns.oid = tbl.relnamespace
      LEFT JOIN pg_stats s ON s.schemaname=ns.nspname
      AND s.tablename = tbl.relname
      AND s.inherited=false
      AND s.attname=att.attname,
      (
        SELECT
          (SELECT current_setting($$block_size$$)::numeric) AS bs,
            CASE WHEN SUBSTRING(SPLIT_PART(v, $$ $$, 2) FROM $$#"[0-9]+.[0-9]+#"%$$ for $$#$$)
              IN ($$8.0$$,$$8.1$$,$$8.2$$) THEN 27 ELSE 23 END AS hdr,
          CASE WHEN v ~ $$mingw32$$ OR v ~ $$64-bit$$ THEN 8 ELSE 4 END AS ma
        FROM (SELECT version() AS v) AS foo
      ) AS constants
      WHERE att.attnum > 0 AND tbl.relkind=$$r$$
      GROUP BY 1,2,3,4,5
    ) AS foo
  ) AS rs
  ON cc.relname = rs.relname AND nn.nspname = rs.nspname
  LEFT JOIN pg_index i ON indrelid = cc.oid
  LEFT JOIN pg_class c2 ON c2.oid = i.indexrelid
) AS sml order by wastedibytes desc limit 5;
```
* 表引膨胀检查
```
SELECT
  current_database() AS db, schemaname, tablename, reltuples::bigint AS tups, relpages::bigint AS pages, otta,
  ROUND(CASE WHEN otta=0 OR sml.relpages=0 OR sml.relpages=otta THEN 0.0 ELSE sml.relpages/otta::numeric END,1) AS tbloat,
  CASE WHEN relpages < otta THEN 0 ELSE relpages::bigint - otta END AS wastedpages,
  CASE WHEN relpages < otta THEN 0 ELSE bs*(sml.relpages-otta)::bigint END AS wastedbytes,
  CASE WHEN relpages < otta THEN $$0 bytes$$::text ELSE (bs*(relpages-otta))::bigint || $$ bytes$$ END AS wastedsize,
  iname, ituples::bigint AS itups, ipages::bigint AS ipages, iotta,
  ROUND(CASE WHEN iotta=0 OR ipages=0 OR ipages=iotta THEN 0.0 ELSE ipages/iotta::numeric END,1) AS ibloat,
  CASE WHEN ipages < iotta THEN 0 ELSE ipages::bigint - iotta END AS wastedipages,
  CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta) END AS wastedibytes,
  CASE WHEN ipages < iotta THEN $$0 bytes$$ ELSE (bs*(ipages-iotta))::bigint || $$ bytes$$ END AS wastedisize,
  CASE WHEN relpages < otta THEN
    CASE WHEN ipages < iotta THEN 0 ELSE bs*(ipages-iotta::bigint) END
    ELSE CASE WHEN ipages < iotta THEN bs*(relpages-otta::bigint)
      ELSE bs*(relpages-otta::bigint + ipages-iotta::bigint) END
  END AS totalwastedbytes
FROM (
  SELECT
    nn.nspname AS schemaname,
    cc.relname AS tablename,
    COALESCE(cc.reltuples,0) AS reltuples,
    COALESCE(cc.relpages,0) AS relpages,
    COALESCE(bs,0) AS bs,
    COALESCE(CEIL((cc.reltuples*((datahdr+ma-
      (CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END))+nullhdr2+4))/(bs-20::float)),0) AS otta,
    COALESCE(c2.relname,$$?$$) AS iname, COALESCE(c2.reltuples,0) AS ituples, COALESCE(c2.relpages,0) AS ipages,
    COALESCE(CEIL((c2.reltuples*(datahdr-12))/(bs-20::float)),0) AS iotta -- very rough approximation, assumes all cols
  FROM
     pg_class cc
  JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname <> $$information_schema$$
  LEFT JOIN
  (
    SELECT
      ma,bs,foo.nspname,foo.relname,
      (datawidth+(hdr+ma-(case when hdr%ma=0 THEN ma ELSE hdr%ma END)))::numeric AS datahdr,
      (maxfracsum*(nullhdr+ma-(case when nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
    FROM (
      SELECT
        ns.nspname, tbl.relname, hdr, ma, bs,
        SUM((1-coalesce(null_frac,0))*coalesce(avg_width, 2048)) AS datawidth,
        MAX(coalesce(null_frac,0)) AS maxfracsum,
        hdr+(
          SELECT 1+count(*)/8
          FROM pg_stats s2
          WHERE null_frac<>0 AND s2.schemaname = ns.nspname AND s2.tablename = tbl.relname
        ) AS nullhdr
      FROM pg_attribute att
      JOIN pg_class tbl ON att.attrelid = tbl.oid
      JOIN pg_namespace ns ON ns.oid = tbl.relnamespace
      LEFT JOIN pg_stats s ON s.schemaname=ns.nspname
      AND s.tablename = tbl.relname
      AND s.inherited=false
      AND s.attname=att.attname,
      (
        SELECT
          (SELECT current_setting($$block_size$$)::numeric) AS bs,
            CASE WHEN SUBSTRING(SPLIT_PART(v, $$ $$, 2) FROM $$#"[0-9]+.[0-9]+#"%$$ for $$#$$)
              IN ($$8.0$$,$$8.1$$,$$8.2$$) THEN 27 ELSE 23 END AS hdr,
          CASE WHEN v ~ $$mingw32$$ OR v ~ $$64-bit$$ THEN 8 ELSE 4 END AS ma
        FROM (SELECT version() AS v) AS foo
      ) AS constants
      WHERE att.attnum > 0 AND tbl.relkind=$$r$$
      GROUP BY 1,2,3,4,5
    ) AS foo
  ) AS rs
  ON cc.relname = rs.relname AND nn.nspname = rs.nspname
  LEFT JOIN pg_index i ON indrelid = cc.oid
  LEFT JOIN pg_class c2 ON c2.oid = i.indexrelid
) AS sml order by wastedbytes desc limit 5;
```
## 5.备份恢复
### 5.1 备份恢复工具汇总
![Image text](../_media/备份汇总.png)
参考：https://wiki.postgresql.org/wiki/Binary_Replication_Tools


## 6.高可用




## 7.新特性
### 7.1 PostgreSQL 10 新特性汇总
PostgreSQL10Beta1 版本于 2017年5月18日发行，PostgreSQL 10 新增了大量新特性，其中特重量级新特性如下：

内置分区表（ Native Table Partitioning）
逻辑复制（Logical Replication）
并行功能增强（Enhancement of Parallel Query）
Quorum Commit for Synchronous Replication
全文检索支持JSON和JSONB数据类型
其它新特性详见 PostgreSQL10 Release ，这里不详细列出，由于时间和精力的关系，目前仅对部分新特性进行演示，详见以下博客：


[PostgreSQL10：重量级新特性-支持分区表](https://postgres.fun/20170521123452.html)
[PostgreSQL10：Parallel Queries 增强](https://postgres.fun/20170521162007.html)
[PostgreSQL10：Additional FDW Push-Down](https://postgres.fun/20170525231345.html)
[PostgreSQL10：逻辑复制（Logical Replication）之一](https://postgres.fun/20170528142004.html)
[PostgreSQL10：逻辑复制（Logical Replication）之二](https://postgres.fun/20170530165846.html)
[PostgreSQL10：Quorum Commit for Synchronous Replication](https://postgres.fun/20170601130120.html)
[PostgreSQL10：Multi-column Correlation Statistics](https://postgres.fun/20170604203859.html)
[PostgreSQL10：新增 pg_hba_file_rules 视图](https://postgres.fun/20170607205537.html)
[PostgreSQL10：全文检索支持 JSON 和 JSONB](https://postgres.fun/20170611204225.html)
[PostgreSQL10：Identity Columns 特性介绍](https://postgres.fun/20170615083732.html)
[PostgreSQL10：Incompatible Changes](https://postgres.fun/20170625210855.html)
[PostgreSQL10：新增 pg_sequence 系统表](https://postgres.fun/20170701151506.html)

### 7.2 PostgreSQL 11 新特性汇总


## 8.案例分析
### 8.1 vacuum freeze报错的问题
* 问题现象
```
template1=> vacuum freeze template1.pg_catalog.pg_authid;
ERROR: found xmin 1988747257 from before relfrozenxid 2810153180
```
* 问题解决方案
makeword
```
可以通过以下任意方式进行修复:
1、重启数据库，重启后会重新读入新数据内容到relcache中，相当于刷新relcache。
2、删除$PGDATA/global/pg_internal.init，这个文件就是存储的relcache的内容，有新的连接连入会创建新的pg_internal.init文件。
```
* 版本修复
```
10.2，9.6.7，9.5.11，9.4.16以后 到 修复版本之间 的版本的PG都会存在相关问题。
10.5, 9.6.10, 9.5.14, 9.4.19 对这个问题进行了修复。

bugfix patch如下: 
https://git.postgresql.org/gitweb/?p=postgresql.git;a=commitdiff;h=817f9f9a8a1932a0cd8c6bc5c9d3e77f6a80e659
```
### 8.2 事务ID用完
在PG中事务年龄不能超过2^31 （2的31次方），如果超过了，这条数据就会丢失。
PG中不允许这种情况出现，当事务的年龄离2^31还有1千万的时候，数据库的日志中就会
有如下告警：
```
warning:database "highgo" must be vacuumed within 177000234 trabnsactions
HINT: To avoid a database shutdown,execute a database-wide VACUUM in "highgo".
```
如果不处理，当事务的年龄离2^31还有1百万时，数据库服务器出于安全考虑，将会自动
禁止任何来自任何用户的连接，同时在日志中是如下信息：
```
error: database is not accepting commands to avoid wraparound data loss in database "highgo"
HINT: Stop the postmaster and use a standalone backend to VACUUM in "highgo".
```
出现这种情况时，只能把数据库启动到单用户模式下，执行VACUUM命令来修复了。
```
postgres --single

PostgreSQL stand-alone backend 9.5.7
backend> vacuum freeze table_name; 或者 vacuum full;
backend> Ctrl + D
```

## 9. python
### 9.1 python 安装
*	pip下载保存Python包，pip离线安装
```
#查看已有的包
pip list
#将已有的包清单,输出到/tmp目录下文件
./pip freeze > /tmp/requirements.txt
#基于列表来进行下载
pip download  -r /tmp/requirements.txt  -d  /tmp/paks/
#安装指定包
pip install   --no-index   --find-links=/soft/packs/   pandas
或者
/anaconda3/bin/pip install /soft/paks/pymongo-3.5.1.tar.gz
注意有先后顺序要去(按照依赖)
```


## 参考
### 运维类
* SQL脚本

https://github.com/HariSekhon/SQL-scripts
https://gist.github.com/rgreenjr/3637525

* PostgreSQL的电子书籍
https://github.com/faisalbasra/postgres_books

*   PostgreSQL入门调优
http://pgtune.leopard.in.ua/

### 内核类
* BUG速查手册
https://github.com/anse1/sqlsmith/wiki#postgresql
* 升级，快速对比版本Release
https://why-upgrade.depesz.com/show?from=9.4&to=9.6.6&keywords=：
*   PostgreSQL的commit
https://commitfest.postgresql.org/
*   官方BUG列表
https://granicus.if.org/pgbugs/
https://www.postgresql.org/list/pgsql-bugs/
*   官方wiki kernal
https://wiki.postgresql.org/wiki/Pgkernel
https://wiki.postgresql.org/wiki/Developer_FAQ

### BLOG
```
PostgreSQL Conference for Users and Developers：https://www.pgcon.org/2020/

中文社区：http://www.postgres.cn/index.php/v2/home

官方wiki：https://wiki.postgresql.org/

DBEnginers：https://db-engines.com/en/

Stackoverflow：http://stackoverflow.com/questions/tagged/postgresql

PostgreSQL Extension network：https://pgxn.org/、http://pgfoundry.org/

Cybertech：https://www.cybertec-postgresql.com/en/blog/

2ndquadrant：http://blog.2ndquadrant.com/en

Internal of PostgreSQL：https://www.interdb.jp/pg/

Bruce Momjian：https://momjian.us/main/presentations/internals.html

Hubert Lubaczewski：https://www.depesz.com/

lbrar Ahmed：http://pgelephant.com/

freeideas：http://postgresql.freeideas.cz/

Percona：https://www.percona.com/blog/2018/10/30/postgresql-locking-part-3-lightweight-locks/

PostgrePro：https://habr.com/en/company/postgrespro/blog/442776/、https://postgrespro.com/education/courses/2dINTRO

PostgreSQL Tutorial（教材类）：https://postgreshelp.com/postgresql_shared_buffers/、https://www.postgresqltutorial.com/、https://www.tutorialspoint.com/postgresql/index.htm

https://madusudanan.com/blog/understanding-postgres-caching-in-depth/

severalnines：https://severalnines.com/blog/tuning-io-operations-postgresql

EnterpriseDB：https://www.enterprisedb.com/blog/tuning-sharedbuffers-and-walbuffers

A curated list of awesome PostgreSQL software：https://github.com/dhamaniasad/awesome-postgres/blob/master/README.md?from=groupmessage&isappinstalled=0

https://www.programmersought.com/

CitusData：https://www.citusdata.com/blog/2018/02/15/when-postgresql-blocks/

PostgreSQL DBA Team：https://dataegret.com/2020/10/postgres-13-observability-updates/

查看参数说明的网站（包括Stackoverflow）：https://postgresqlco.nf/doc/en/param/vacuum_cleanup_index_scale_factor/

查看参数说明的网站（包括commit list）：https://pgpedia.info/h/hash_mem_multiplier.html

PostgreSQL数据库的学习交流平台（中启乘数）：http://www.pgsql.tech/

slideshare：https://www.slideshare.net/noriyoshishinoda/pgconfasia-2017-logical-replication-internals-english?from_action=save

BlockInternal：https://fritshoogland.wordpress.com/category/postgresql/

PostgreSQL(数据库)资料：https://github.com/ty4z2008/Qix/blob/master/pg.md

ITPub：https://z.itpub.net/stack/detail/10026

DBIservice：https://blog.dbi-services.com/tag/postgresql/

https://akorotkov.github.io/
```

### 国内优质博客类
```
何小栋（海量内核大佬）：http://blog.itpub.net/6906/list/1/

冯若航（探探全栈 PostgreSQL DBA）：http://v0.pigsty.cc/zh/blog/2021/03/03/postgres%E9%80%BB%E8%BE%91%E5%A4%8D%E5%88%B6%E8%AF%A6%E8%A7%A3/#%E5%B1%80%E9%99%90%E6%80%A7

德哥（步道师）：https://github.com/digoal/blog

陈华军：https://github.com/ChenHuajun/blog_xqhx

张晋：https://zhangeamon.top/postgresql/

刘阳明：http://liuyangming.tech/

https://www.mengqingzhong.com/2021/01/01/postgresql-index-system-catalog-tables/

https://zhmin.github.io/posts/postgresql-toast/

https://www.cnblogs.com/abclife/p/14869975.html

https://foucus.blog.csdn.net/article/list/1

https://blog.csdn.net/qq_43687755/category_10189967.html

https://tonydong.blog.csdn.net/
```

### 高可用
*   PG HA支持工具的选型
https://scalegrid.io/blog/managing-high-availability-in-postgresql-part-1/


*   Patroni官网
https://patroni.readthedocs.io/en/latest/


*   Pigsty
https://pigsty.cc/

*   PG 超赞合集
https://asmcn.icopy.site/awesome/awesome-postgres/

* postgresql参数文档
https://postgresqlco.nf/

### 驱动
*   驱动
https://jdbc.postgresql.org/documentation/head/connect.html#connection-parameters


