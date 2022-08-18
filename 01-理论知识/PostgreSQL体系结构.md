# PostgreSQL体系结构

## 1 Postmaster进程
*   数据库的启停
*   监听客户端连接
*   为每个客户端连接衍生(fork)专用的postgresql服务进程
*   当postgresql进程出错时尝试修复
*   管理数据文件
*   管理数据库的辅助进程

## 2 PostgreSQL进程
*   直接与客户端进程通讯
*   负责接收客户端所有的请求
*   包含数据库引擎，负责解析SQL和生成执行计划等
*   根据命令的需要调用各中辅助进程和访问各内存结构
*   负责返回命令执行结果给客户端
*   在客户端断开连接时释放进程


## 3 本地内存
本地内存是服务器进程独占的内存结构，每个postgresql子进程都会分配一小块相应内存空间，随着连接会话的增加而增加，它不属于实例的一部分
*   work_mem：用于排序的内存
*   maintenance_work_mem：用于内部运维工作的内存，如VACUUM垃圾回收、创建和重建索引等等
*   temp_buffers：用于存储临时表的数据


## 4 共享内存
*   Shared Buffer：
    -用于缓存表和索引的数据块
    -数据的读写都是直接对BUFFER操作的，若所需的块不再缓存中，则需要从磁盘中读取
    -在buffer中被修改过的，但又没有写到磁盘文件中的块被称之为脏块
    -由shared_buffers参数控制尺寸
*   WAL(Write Ahead Log) Buffer：
    -预写日志缓存用于缓存增删改等写操作产生的事务日志
    -由wal_buffers参数控制尺寸
*   Clog Buffer：
    -Commit Log Buffer是记录事务状态的日志缓存

## 5 辅助进程
*   Backgroup writer：
    -工作任务是将shared buffer中的脏数据页写到磁盘文件中
    -使用LRU算法进行清理脏页
    -平时多在休眠，被激活时工作


*   Autovacuum launcher/workers：
    -自动清理垃圾回收进程
    -当参数autovacuum设为on的时候启用自动清理功能
    -Launcher为清理的守护进程，每次启动的时候会调用一个或多个worker
    -Worker是负责真正清理工作的进程，由autovacuum_max_workers参数设定其数量


*   WAL writer：
    -将预写日志写入磁盘文件
    -触发时机：WAL BUFFER满了
        事务commit时；
        WAL writer进程到达间歇时间时；
    -checkpoint发生时；


*   Checkpoint：
    -用于保证数据库的一致性
    -它会触发bgwriter和wal writer动作
    -拥有多个参数控制其启动的间隔
作用：
一般checkpoint会将某个时间点之前的脏数据全部刷新到磁盘，以实现数据的一致性与完整性。其主要目的是为了缩短崩溃恢复时间

Checkpoint 具体工作:
```
记录检查点的开始位置，记录为 redo point（重做位点）
将 shared buffer 中的数据刷到磁盘里面去
刷脏结束，检查点之前的数据均已被刷到磁盘存储（数据1和2）
记录相关信息
将最新的检测点记录在 pg_control 文件中
```

触发条件:
```
超级用户（其他用户不可）执行CHECKPOINT命令
数据库shutdown
数据库recovery完成
XLOG日志量达到了触发checkpoint阈值
周期性地进行checkpoint,周期内无写入不执行checkpoint
需要刷新所有脏页
```

相关参数:
```
Postgresql 10

checkpoint_timeout = 5min               # range 30s-1d
max_wal_size = 2GB
min_wal_size = 1GB
checkpoint_completion_target = 0.9      # checkpoint target duration, 0.0 - 1.0
#checkpoint_flush_after = 256kB         # measured in pages, 0 disables
#checkpoint_warning = 30s               # 0 disables
```
checkpoint_segments WAL log的最大数量，系统默认值是3。超过该数量的WAL日志，会自动触发checkpoint。 新版(9.6)使用min_wal_size, max_wal_size 来动态控制wal日志
checkpoint_timeout 系统自动执行checkpoint之间的最大时间间隔。系统默认值是5分钟。
checkpoint_completion_target 该参数表示checkpoint的完成时间占两次checkpoint时间间隔的比例，系统默认值是0.5,也就是说每个checkpoint需要在checkpoints间隔时间的50%内完成。
checkpoint_warning 系统默认值是30秒，如果checkpoints的实际发生间隔小于该参数，将会在server log中写入一条相关信息。可以通过设置为0禁用。

通过 pg_stat_bgwriter 视图查看
```
select checkpoints_timed,checkpoints_req,checkpoint_write_time,buffers_checkpoint,buffers_clean from pg_stat_bgwriter ;
```



*   Syslogger：
```
    采集postgresql的运行状态，并将运行日志写入日志文件
    logging_collector参数为on时启动，不建议关闭
    log_directory设定日志目录
    log_destination设定日志输出方式，甚至格式
    log_filename设定日志文件名
    log_truncate_on_rotation设定是否重复循环使用且删除日志
    log_rotation_age设定循环时间
    log_rotation_size设定循环的日志尺寸上线
```


*   Archiver：
    用于将写满的WAL日志文件转移到归档目录，该进程只有在归档模式才会启用

*   Statistics Collector：
    统计信息的收集进程。收集表和索引的空间信息和元组信息等，甚至是表的访问信息。收集到的信息除了能被优化器使用以外，还有autovaccum也能利用，甚至给数据库管理员作为数据库管理的参考信息.

## 6 目录结构
```
    base： 该目录包含数据库用户所创建的各个数据库，同时也包括postgres、template0和template1的pg_default tablespace
    pg_wal：该目录包含wal日志。
            日志文件默认为16M，编译安装时可指定大小： --with-wal-segsize=64（64M）格式：	000000010000000000000008
　　         当空间不足，导致数据库启动不了。可以把比较旧的xlog移动到别的目录。
　　         wal_keep_segments=100   保留文件数。占用空间wal_keep_segments*16M
    log： 该目录包含数据库日志。(目录名可自定义)
    global： 该目录包含集群范围的各个表和相关视图。 （ pg_database、 pg_tablespace ）pg_clog： 该目录包含事务提交状态数据。文件并不大，不需要特别维护。
    pg_multixact： 该目录包含多事务状态数据（等待锁定的并发事务）
    pg_notify ：该目录包含LISTEN/NOTIFY状态数据。
    pg_serial：该目录包含了已经提交的序列化事务的有关信息。
    pg_snapshots：该目录包含导出的快照。
    pg_stat_tmp：该目录包含统计子系统的临时文件。
    pg_subtrans：该目录包含子事务状态数据。
    pg_tblspc：该目录包含表空间的符号链接。
    pg_twophase：该目录包含预备事务的状态文件。
    pg_commit_ts：该目录包含已提交事务的时间。
    pg_dynshmem：该目录包含动态共享内存子系统使用的文件。
    pg_logical：该目录包含逻辑解码的状态数据。
    pg_replslot：该目录包含复制槽数据。
    pg_stat：该目录包含统计子系统的永久文件。
    PG_VERSION：包含版本信息。
```