# 前奏

## 1.PostgreSQL高可用列表
![Image text](./_media/t_has.png)

引用：https://wiki.postgresql.org/wiki/Replication,_Clustering,_and_Connection_Pooling

## 2. 介绍
### 2.1 发展现状
Release notes：https://patroni.readthedocs.io/en/master/releases.html#releases


#### 2.2 安装要求
yum：postgresql-devel   haproxy libyaml python watchdog  
pip：psycopg2-binary python-psycopg2  patroni[etcd,aws]

#### 2.3 patroni configuration
patroni PostgreSQL 默认值：
```
max_connections: 100
max_locks_per_transaction: 64
max_worker_processes: 8
max_prepared_transactions: 0
wal_level: hot_standby
wal_log_hints: on
track_commit_timestamp: off
```

custom_conf 参数
Patroni加载postgresql conf优先级：

* load parameters from file postgresql.base.conf (or from a custom_conf file, if set)
* load parameters from file postgresql.conf
* load parameters from file postgresql.auto.conf
* run-time parameter using -o –name=value

#### 2.4 Patroni REST API

健康检查点：

curl -s http://localhost:8008/patroni | jq .

集群状态:

 curl -s http://localhost:8008/cluster | jq .

 历史检查点：

 curl -s http://localhost:8008/history | jq .

配置检查点：

curl -s http://localhost:8008/config | jq .

####  2.5 Patroni YAML configuration

#####  2.5.1 动态配置

* loop_wait: 循环休眠的秒数 默认值：10s
* ttl:获得leader锁的ttl(秒)。可以把它看作是启动自动故障转移过程之前的时间长度。默认值:30
* retry_timeout:DCS和PostgreSQL操作重试的超时(以秒为单位)。DCS或网络问题在此之前不会导致主库降级。默认值:10
* Maximum_lag_on_failover:跟随者可以延迟参与leader选举的最大字节数。
* max_timelines_history: DCS中保存的时间轴历史条目的最大数量。默认值:0。当设置为0时，它将在DCS中保留完整的历史记录。
* Master_start_timeout:在触发故障转移之前允许主服务器从故障中恢复的时间(以秒为单位)。默认值是300秒。如果设置为0，则在检测到崩溃后立即进行故障转移(如果可能的话)。当使用异步复制时，故障转移可能导致事务丢失。主故障的最坏情况下的故障转移时间是:loop_wait + master_start_timeout + loop_wait，除非master_start_timeout为零，在这种情况下它只是loop_wait。根据持久性/可用性权衡来设置该值。
* master_stop_timeout:暂停Postgres时允许Patroni等待的秒数，只有启用synchronous_mode时才有效。当设置为> 0且启用了synchronous_mode时，如果停止操作运行的时间超过了master_stop_timeout设置的值，那么Patroni将向master发送SIGKILL。根据持久性/可用性权衡来设置该值。如果该参数未设置或设置<= 0，则master_stop_timeout不适用。
* Synchronous_mode:开启同步复制模式。在这种模式下，一个副本将被选择为同步副本，并且只有最新的leader和同步副本能够参与leader选举。同步模式确保成功提交的事务不会在故障转移时丢失，但代价是当Patroni无法确保事务持久性时，会失去写操作的可用性。
* Synchronous_mode_strict:如果没有可用的同步副本，防止禁用同步复制，阻止所有客户端写主服务器。

* PostgreSQL
    ```
    Use_pg_rewind:是否使用pg_rewind。默认值为false  一般设置为 ： true
    Use_slots:是否使用复制槽      一遍设置为： true
    ```

#####  2.5.2 全局配置
* name: 主机的名称。对集群来说必须是唯一的。
* namespace: 配置存储中的路径，Patroni将在其中保存关于集群的信息。默认值:'/service'
* scope: 集群名称

##### 2.5.3 日志
* level: 设置常规日志级别。默认值为INFO
* traceback_level: 设置回溯可见的级别。默认值为ERROR。如果您希望仅在启用log.level=DEBUG时才能查看回溯，则将其设置为DEBUG
* format: 设置日志格式化字符串。默认值是%(asctime)s %(levelname)s: %(message)s
* dir: 应用程序日志写入目录。该目录必须存在，并且被执行Patroni的用户写入。如果设置了这个值，应用程序将默认保留4个25MB的日志。您可以使用file_num和file_size调整这些保留值(参见下面)。
* file_num: 要保留的应用程序日志数量。
* file_size: 触发日志滚动的patroni.log文件大小(以字节为单位)。

具体python日志格式可见：https://docs.python.org/3.6/library/logging.html#logrecord-attributes


#####  2.5.4 Bootstrap  设置
* initdb：
    ```
    —data-checksum:在9.3上需要pg_rewind时必须启用。
    —encoding: UTF8:新数据库的默认编码。
    - locale: UTF8:新数据库的默认区域。
    ```

* pg_hba:
    ```
    - host all all 0.0.0.0/0 md5.
    - host replication replicator 127.0.0.1/32 
    ```
* users:  初始化新集群后需要创建的一些附加用户

##### 2.5.5 PostgreSQL
* pg_ctl_timeout:执行启动、停止或重启时，pg_ctl应该等待多长时间。缺省值是60秒
* Watchdog
    ```
    mode: on/off
    device:  Path to watchdog device. Defaults to /dev/watchdog.
    safety_margin: 失效时间
    ```

#### 2.6 patroni system 配置
编辑has服务配置文件，${HAS_PATH}为HAS的安装目录，请务必注意替换
```
vi /usr/lib/systemd/system/has.service
[Unit]
Description=Vastbase HAS server daemon
After=network.target dcs.service

[Install]
WantedBy=multi-user.target

[Service]
Type=exec
User=vastbase
EnvironmentFile=-/etc/sysconfig/vastbase-has
ExecStart=${HAS_PATH}/bin/has $CONFIG_FILE
ExecStopPost=/bin/sudo /usr/sbin/ip addr del ${VIP}/${VIPNETMASKBIT} dev ${VIPDEV} label ${VIPDEV}:${VIPLABEL}
Restart=no
LimitMEMLOCK=infinity
LimitNOFILE=1024000
TimeoutStopSec=600
```

配置/etc/sysconfig/vastbase-has
```
vi /etc/sysconfig/vastbase-has
PYTHONPATH=${HAS_PATH}/lib/python2.7/site-packages
CONFIG_FILE=/home/vastbase/patroni/vastbase.yml
VIP=172.16.101.124
VIPBRD=172.16.103.255
VIPNETMASK=255.255.252.0
VIPNETMASKBIT=22
VIPDEV=enpls0
VIPLABEL=1
```

#### 2.7  Patroni 常用查询
* 集群信息查询
```
vastbase=#   SELECT CASE WHEN pg_catalog.pg_is_in_recovery() THEN 0 ELSE ('x' || pg_catalog.substr(pg_catalog.pg_xlogfile_name(pg_catalog.pg_current_xlog_location()), 1, 8))::bit(32)::int END, CASE WHEN pg_catalog.pg_is_in_recovery() THEN GREATEST( pg_catalog.pg_xlog_location_diff(COALESCE(pg_catalog.pg_last_xlog_receive_location(), '0/0'), '0/0')::bigint, pg_catalog.pg_xlog_location_diff((select lsn from pg_catalog.pg_last_xlog_replay_location()), '0/0')::bigint)ELSE pg_catalog.pg_xlog_location_diff(pg_catalog.pg_current_xlog_location(), '0/0')::bigint END;
 case | pg_xlog_location_diff 
------+-----------------------
    1 |         2626837183184
(1 row)

vastbase=# 
```
* 同步备节点查询
```
vastbase=#   SELECT pg_catalog.lower(pg_catalog.left(pg_catalog.substr(application_name, pg_catalog.strpos(application_name,'[') + 1),-1)), pg_catalog.lower(state), pg_catalog.lower(sync_state) FROM pg_catalog.pg_stat_replication ORDER BY receiver_flush_location DESC;
 lower |   lower   | lower 
-------+-----------+-------
 vdb2  | streaming | sync
(1 row)
```

