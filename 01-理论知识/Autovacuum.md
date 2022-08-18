## vacuum 垃圾回收器

### 介绍
数据库总是不断地在执行删除，更新等操作。良好的空间管理非常重要，能够对性能带来大幅提高。在postgresql中用于维护数据库磁盘空间的工具是VACUUM，其重要的作用是删除那些已经标示为删除的数据并释放空间。 postgresql中执行delete,update操作后，表中的记录只是被标示为删除状态，并没有释放空间，在以后的update或insert操作中该部分的空间是不能够被重用的。经过vacuum清理后，空间才能得到释放。


### 意义
PostgreSQL每个表和索引的数据都是由很多个固定尺寸的页面存储（通常是 8kB，不过在编译服务器时[–with-blocksize]可以选择其他不同的尺寸）
PostgreSQL中数据操作永远是Append操作,具体含义如下:
```
insert 时向页中添加一条数据
update 将历史数据标记为无效,然后向页中添加新数据
delete 将历史数据标记为无效
```
因为这个特性,所以需要定期对数据库vacuum,否则会导致数据库膨胀,建议打开autovacuum.

### 参数
* FULL
Selects “full” vacuum, which can reclaim more space, but takes much longer and exclusively locks the table. This method also requires extra disk space, since it writes a new copy of the table and doesn’t release the old copy until the operation is complete. Usually this should only be used when a significant amount of space needs to be reclaimed from within the table.
大招，需要更多的磁盘空间，空间将会被重新整理。　auto vacumm 只删除空间，并没有整理使空间更紧凑。

* VERBOSE
Prints a detailed vacuum activity report for each table.
打印回收时每个table 执行细节

* ANALYZE
Updates statistics used by the planner to determine the most efficient way to execute a query.
统计库


### 扩展阅读
* 1.回收空间

这个通常是大家最容易想起来的功能。回收空间，将dead tuple清理掉。但是已经分配的空间，一般不会释放掉。除非做vacuum full，但是需要exclusive lock。一般不太建议，因为如果表最终还是会涨到 这个高水位上，经常做vacuum full意义不是非常大。一般合理设置vacuum参数，进行常规vacuum也就够了。

* 2.冻结tuple的xid

PG会在每条记录（tuple）的header中，存放xmin,xmax信息(增删改事务ID)。transactionID的最大值为2的32次，即无符整形来表示。当transactionID超过此最大值后，会循环使用。 这会带来一个问题：就是最新事务的transactionID会小于老事务的transactionID。如果这种情况发生后，PG就没有办法按transactionID来区分事务的先后，也没有办法实现MVCC了。因此PG用vacuum后台进程， 按一定的周期和算法触发vacuum动作，将过老的tuple的header中的事务ID进行冻结。冻结事务ID，即将事务ID设置为“2”（“0”表示无效事务ID；“1”表示bootstrap，即初始化；“3”表示最小的事务ID）。PG认为被冻结的事务ID比任何事务都要老。这样就不会出现上面的这种情况了。

* 3.更新统计信息

vacuum analyze时，会更新统计信息，让PG的planner能够算出更准确的执行计划。autovacuum_analyze_threshold和autovacuum_analyze_scale_factor参数可以控制analyze的触发的频率。

* 4.更新visibility map

在PG中，有一个visibility map用来标记那些page中是没有dead tuple的。这有两个好处，一是当vacuum进行scan时，直接可以跳过这些page。二是进行index-only scan时，可以先检查下visibility map。这样减少fetch tuple时的可见性判断，从而减少IO操作，提高性能。另外visibility map相对整个relation，还是小很多，可以cache到内存中。


### vacuum参数介绍

autovacuum 触发条件，大致有以下几个：
```
autovacuum：默认为on，表示是否开起autovacuum。默认开起。特别的，当需要冻结xid时，尽管此值为off，PG也会进行vacuum。
autovacuum_naptime：下一次vacuum的时间，默认1min。 这个naptime会被vacuum launcher分配到每个DB上。autovacuum_naptime/num of db。
log_autovacuum_min_duration：记录autovacuum动作到日志文件，当vacuum动作超过此值时。 “-1”表示不记录。“0”表示每次都记录。
autovacuum_max_workers：最大同时运行的worker数量，不包含launcher本身。
autovacuum_vacuum_threshold:默认50。与autovacuum_vacuum_scale_factor配合使用， autovacuum_vacuum_scale_factor默认值为20%。
                          当update,delete的tuples数量超过autovacuum_vacuum_scale_factor*table_size+autovacuum_vacuum_threshold时，进行vacuum。如果要使vacuum工作勤奋点，则将此值改小。
autovacuum_analyze_threshold:默认50。与autovacuum_analyze_scale_factor配合使用, autovacuum_analyze_scale_factor默认10%。
                          当update,insert,delete的tuples数量超过autovacuum_analyze_scale_factor*table_size+autovacuum_analyze_threshold时，进行analyze。
autovacuum_freeze_max_age和autovacuum_multixact_freeze_max_age：前面一个200 million,后面一个400 million。离下一次进行xid冻结的最大事务数。
autovacuum_vacuum_cost_delay：如果为-1，取vacuum_cost_delay值。
autovacuum_vacuum_cost_limit：如果为-1，到vacuum_cost_limit的值，这个值是所有worker的累加值。
```
基于代价的vacuum参数:
```
vacuum_cost_delay ：计算每个毫秒级别所允许消耗的最大IO，vacuum_cost_limit/vacuum_cost_dely。 默认vacuum_cost_delay为20毫秒。
vacuum_cost_page_hit ：vacuum时，page在buffer中命中时，所花的代价。默认值为1。
vacuum_cost_page_miss：vacuum时，page不在buffer中，需要从磁盘中读入时的代价默认为10。 vacuum_cost_page_dirty：当vacuum时，修改了clean的page。这说明需要额外的IO去刷脏块到磁盘。默认值为20。
vacuum_cost_limit：当超过此值时，vacuum会sleep。默认值为200。
把上面每个cost值调整的小点，然后把limit值调的大些，可以延长每次vacuum的时间。这样做，如果在高负载的系统当中，可能IO会有所影
```

### 实战
autovacuum 在达到触发条件时就会执行。如果触发在业务高峰时发生，对线上的业务性能会带来影响。应避免。

数据库的vacuum 为可控的，避免autovacuum对线上数据库在运行高峰时的影响。

在必要时进行手动执行vacuum ,在业务低峰期执行。

监控数据库的autovacuum ，使其在达到触发条件前被及时发现。

### DBA 维护
参考表空间膨胀率计算执行预期效果
执行前设置 maintenance_work_mem 增加临时使用内存
执行前设置 vacuum_cost_delay , vacuum_cost_limit 调整处理速度
执行vacuum VERVOSE ANALYZE
执行analyze 更新统计信息
进度查看 select * from pg_stat_progress_vacuum ;
注意wal 生成速率，可能会造成从库落后过多。wal找不到错误。从库需要重新拉取
注意业务峰值期对业务的造成影响
系统IO，主从主机带宽



autovacuum会在两种情况下会被触发：
1、当update,delete的tuples数量超过 autovacuum_vacuum_scale_factor * table_size + autovacuum_vacuum_threshold
2、指定表上事务的最大年龄配置参数autovacuum_freeze_max_age，默认为2亿，达到这个阀值将触发 autovacuum进程，从而避免 wraparound。

### 建议：
1、autovacuum_max_workers的建议值为CPU核数/3。CPU资源充足，I/O性能较好时，可以适当加大。
2、对于更新频繁的交易系统，如果系统资源充足，可以缩小autovacuum_vacuum_scale_factor 与 autovacuum_vacuum_threshold，让vacuum清理频繁


### 更改系统autovacuum相关参数
```
ALTER SYSTEM SET autovacuum_vacuum_scale_factor = 0.03;
ALTER SYSTEM SET autovacuum_analyze_scale_factor = 0.03;
ALTER SYSTEM SET autovacuum_vacuum_threshold = 300;
ALTER SYSTEM SET autovacuum_analyze_threshold = 300;
select pg_reload_conf ();
```
* 更改单表autovacuum相关参数
```
alter table tableA set (autovacuum_vacuum_scale_factor=0.03);
```
* 修改单表注意点：
```
    1.autovacuum_analyze_scale_factor如果修改单表autovacuum_analyze_scale_factor 会            AccessExclusiveLock 锁
        SQL会占AccessShareLock 锁
    2.注意如果是用ALTER TABLE设置的存储参数,设置好后并不会生效,需要重新vacuum full表后才会生效.
    3.如果修改fillfactor 页填充率必须对重新vacuum full表后才会生效

```

* for example
```
--修改单表状态参数
postgres=#  \h alter table
Command:     ALTER TABLE
Description: change the definition of a table
    SET ( storage_parameter [= value] [, ... ] )
    RESET ( storage_parameter [, ... ] )

--创建前置表
CREATE TABLE alter_tab(
 id int,
 name varchar);
 
--添加单表参数
ALTER TABLE alter_tab SET (fillfactor=80,autovacuum_enabled, autovacuum_analyze_scale_factor  = 0.3,autovacuum_analyze_threshold = 300);

--去除单表参数
ALTER TABLE alter_tab RESET (autovacuum_enabled,autovacuum_analyze_scale_factor);

--查看单表参数
SELECT reloptions FROM pg_class WHERE oid = 'alter_tab'::regclass;
```



### 背景信息
ANALYZE 语句可收集与数据库中表内容相关的统计信息，统计结果存储在系统表 PG_STATISTIC 中。
查询优化器会使用这些统计数据，以生成最有效的执行计划。
建议在执行了大批量插入/删除操作后，例行对表或全库执行 ANALYZE 语句更新统计信息。目前默认
收集统计信息的采样比例是 30000 行（即：guc 参数 default_statistics_target 默认设置为 100），如果
表的总行数超过一定行数（大于 1600000），建议设置 guc 参数 default_statistics_target 为-2，即按2%收集样本估算统计信息。
对于在批处理脚本或者存储过程中生成的中间表，也需要在完成数据生成之后显式的调用 ANALYZE。
对于表中多个列有相关性且查询中有同时基于这些列的条件或分组操作的情况，可尝试收集多列统计
信息，以便查询优化器可以更准确地估算行数，并生成更有效的执行计划。 操作步骤
使用以下命令更新某个表或者整个 database 的统计信息。
ANALYZE tablename; --更新单个表的统计信息
ANALYZE; --更新全库的统计信息
使用以下命令进行多列统计信息相关操作。
ANALYZE tablename ((column_1, column_2)); --收集 tablename 表的 column_1、column_2
列的多列统计信息
ALTER TABLE tablename ADD STATISTICS ((column_1, column_2)); --添加 tablename 表的 column_1、column_2
列的多列统计信息声明
ANALYZE tablename; --收集单列统计信息，并收集已声明的多列统计信息
ALTER TABLE tablename DELETE STATISTICS ((column_1, column_2)); --删除 tablename 表的 column_1、column_2
列的多列统计信息或其声明

* 注意点
在使用 ALTER TABLE tablename ADD STATISTICS 语句添加了多列统计信息声明后，系统并不会立刻收集多列统计
信息，而是在下次对该表或全库进行 ANALYZE 时，进行多列统计信息的收集。

* GUC参数介绍
![Image text](./_media/企业微信截图_16511983651590.png)
![Image text](./_media/企业微信截图_16511982695053.png)

* 优化器选项
```
ALTER session set default_statistics_target=-50;
show default_statistics_target;
analyze lcinsured;
analyze lccont;
```
* 单独为用户设置
```
alter user   grp_nd set  default_statistics_target to -25;
```

* 手动添加多列统计信息 注意点：会有锁 （AccessExclusiveLock）
```
cicgroup=> ALTER TABLE lccont ADD STATISTICS ((contno,insuredno));
ALTER TABLE

```

* 统计信息系统表 PG_STATISTIC
```
select  oid from pg_class where relname='lcpol';
select * from pg_statistic where starelid=8867127;
select starelid,starelkind,staattnum,stanullfrac,stawidth,stadistinct,stakind1,stanumbers1,stavalues1,stavalues2,stavalues3 from pg_statistic where starelid=8867127;
```




### 参考文档
https://blog.csdn.net/u012551524/article/details/120548763
https://www.cnblogs.com/VicLiu/p/11854730.html
https://www.jianshu.com/p/9a34b9610012
https://blog.csdn.net/kmblack1/article/details/84953517
 