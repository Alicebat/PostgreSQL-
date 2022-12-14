# 基于Patroni的Citus高可用环境部署

## 1. 前言

Citus是一个非常实用的能够对PostgreSQL进行水平扩展的解决方案，或者说是一款基于PostgreSQL的分布式HTAP数据库。本文简单说明Citus HA的技术方案，并实际演示一下搭建Citus HA环境的步骤。



## 2. 技术方案

### 2.1 Citus HA方案选型

Citus集群由一个CN节点和N个Worker节点组成。CN节点的高可用可以使用任何通用的PG 高可用方案，即为CN节点通过流复制配置主备2台PG机器；Worker节点的高可用除了可以像CN一样采用PG原生的高可用方案，还支持另一种多副本分片的高可用方案。

多副本高可用方案是Citus早期版本默认的worker高可用方案（当时`shard_count`默认值为2），这种方案部署非常简单，而且坏一个worker节点也不影响业务。在多副本高可用中，每次写入数据时，CN节点需要在2个worker上分别写数据，这也带来一系列不利的地方。

1. 数据写入的性能下降
2. 对多个副本的数据一致性的保障也没有PG原生的流复制强
3. 存在功能上的限制，比如不支持Citus MX架构

因此，Citus的多副本高可用方案适用场景有限，Citus 官方文档上也说可能它只适用于append only的业务场景,不作为推荐的高可用方案了(在Citus 6.1的时候，`shard_count`默认值从2改成了1)。



因此，建议Citus和CN和Worker节点都使用PG的原生流复制部署高可用。



### 2.2 PG HA支持工具的选型

PG本身提供的流复制的HA的部署和维护都不算很复杂，但是如果我们追求更高程度的自动化，特别是自动故障切换，可以使用一些使用第3方的HA工具。目前有很多种可选的开源工具，下面几种算是比较常用的

- PAF(PostgreSQL Automatic Failover)
- repmgr
- Patroni

它们的比较可以参考: https://scalegrid.io/blog/managing-high-availability-in-postgresql-part-1/



其中patroni采用DCS存储元数据，能够严格的保障元数据的一致性，可靠性高；而且它的功能也比较强大。

因此个人推荐使用patroni（只有2台机器无法部署etcd的情况可以考虑其它方案）。本文也基于patroni演示Citus高可用的部署。



## 2.3 客户端流量切换方案

PG 主备切换后，访问数据库的客户端也要相应地连接到新的主库。目前常见的有下面几种方案：

- HA Proxy

  - 优点
    - 可靠
    - 支持负载均衡

   - 缺点
     	- 性能损耗
        	- haproxy自身的HA

- VIP

  - 优点
    - 无性能损耗，不占用机器资源
  - 缺点
    - 主备节点IP必须在同网段

- 客户端多主机URL

  - 优点
    - 无性能损耗，不占用机器资源
    - 不依赖VIP，易于在云环境部署
    - pgjdbc支持读写分离和负载均衡

  - 缺点
    - 仅部分客户端驱动支持(目前包括pgjdbc，libpq和基于libpq的驱动，如python和php)
    - 如果数据库层面没控制好出现了"双主"， 客户端同时向2个主写数据的风险较高

  

对于Citus集群情况稍有不同，推荐的候选方案如下

- 应用连接Citus
  - 客户端多主机URL
  - VIP
- Citus CN连接Worker
  - VIP
  - worker节点发生切换时动态修改Citus CN上的worker节点元数据



在条件许可的情况下，推荐采用客户端多主机URL访问Citus，但考虑到有些开发语言的驱动不支持多主机URL，因此本文演示的方案如下

- 客户端通过VIP连接Citus CN
  - 通过patroni回调动态配置读写VIP
  - 通过keepalived配置只读VIP

- worker节点发生切换时动态修改Citus CN上的worker节点元数据



## 3. 实验环境

**主要软件**

- CentOS 7.8
- PostgreSQL 12
- Citus 10.4
- patroni 1.6.5
- etcd 3.3.25



**机器和vip资源**

- Citus CN
  - node1：192.168.234.201 
  - node2：192.168.234.202 
- Citus Worker
  - node3：192.168.234.203 
  - node4：192.168.234.204
- etcd
  - node4：192.168.234.204
- VIP（Citus CN )
  - 读写VIP：192.168.234.210
  - 只读VIP：192.168.234.211



**环境准备**

所有节点设置时钟同步

```
yum install -y ntpdate
ntpdate time.windows.com && hwclock -w
```

如果使用防火墙需要开放postgres，etcd和patroni的端口。

- postgres:5432
- patroni:8000
- etcd:2379/2380

更简单的做法是将防火墙关闭

```
setenforce 0
sed -i.bak "s/SELINUX=enforcing/SELINUX=permissive/g" /etc/selinux/config
systemctl disable firewalld.service
systemctl stop firewalld.service
iptables -F
```



## 4. etcd部署

因为本文的主题不是etcd的高可用，所以只在node4上部署单节点的etcd用于实验。部署步骤如下



安装需要的包

```
yum install -y gcc python-devel epel-release
```

安装etcd

```
yum install -y etcd
```

编辑etcd配置文件`/etc/etcd/etcd.conf`, 参考配置如下

```
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"
ETCD_LISTEN_PEER_URLS="http://192.168.234.204:2380"
ETCD_LISTEN_CLIENT_URLS="http://localhost:2379,http://192.168.234.204:2379"
ETCD_NAME="etcd0"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://192.168.234.204:2380"
ETCD_ADVERTISE_CLIENT_URLS="http://192.168.234.204:2379"
ETCD_INITIAL_CLUSTER="etcd0=http://192.168.234.204:2380"
ETCD_INITIAL_CLUSTER_TOKEN="cluster1"
ETCD_INITIAL_CLUSTER_STATE="new"
```

启动etcd

```
systemctl start etcd
```



设置etcd自启动

```
systemctl enable etcd
```



## 5. PostgreSQL + Citus + Patroni HA部署

在需要运行PostgreSQL的实例上安装相关软件



安装PostgreSQL 12和Citus

```
yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm

yum install -y postgresql12-server postgresql12-contrib
yum install -y citus_12
```



安装patroni 

```
yum install -y gcc epel-release
yum install -y python-pip python-psycopg2 python-devel

pip install --upgrade pip
pip install --upgrade setuptools
pip install patroni[etcd]
```



创建PostgreSQL数据目录

```
mkdir -p /pgsql/data
chown postgres:postgres -R /pgsql
chmod -R 700 /pgsql/data
```



创建partoni service配置文件`/etc/systemd/system/patroni.service`

```
[Unit]
Description=Runners to orchestrate a high-availability PostgreSQL
After=syslog.target network.target
 
[Service]
Type=simple
User=postgres
Group=postgres
ExecStart=/usr/bin/patroni /etc/patroni.yml
KillMode=process
TimeoutSec=30
Restart=no
 
[Install]
WantedBy=multi-user.targ
```



创建patroni配置文件`/etc/patroni.yml`,以下是node1的配置示例

```
scope: cn
namespace: /service/
name: pg1

restapi:
  listen: 0.0.0.0:8000
  connect_address: 192.168.234.201:8000

etcd:
  host: 192.168.234.204:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    master_start_timeout: 300
    synchronous_mode: false
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        listen_addresses: "0.0.0.0"
        port: 5432
        wal_level: logical
        hot_standby: "on"
        wal_keep_segments: 1000
        max_wal_senders: 10
        max_replication_slots: 10
        wal_log_hints: "on"
        max_connections: "100"
        max_prepared_transactions: "100"
        shared_preload_libraries: "citus"
        citus.node_conninfo="sslmode=prefer"
        citus.replication_model: streaming
        citus.task_assignment_policy: round-robin

  initdb:
  - encoding: UTF8
  - locale: C
  - data-checksums

  pg_hba:
  - host replication repl 0.0.0.0/0 md5
  - host all all 0.0.0.0/0 md5

postgresql:
  listen: 0.0.0.0:5432
  connect_address: 192.168.234.201:5432
  data_dir: /pgsql/data
  bin_dir: /usr/pgsql-12/bin

  authentication:
    replication:
      username: repl
      password: "123456"
    superuser:
      username: postgres
      password: "123456"

tags:
    nofailover: false
    noloadbalance: false
    clonefrom: false
    nosync: false
```

其他PG节点的patroni.yml需要相应修改下面4个参数

- scope
  - node1，node2设置为cn
  - node3，node4设置为wk1
- name
  - node1~node4分别设置pg1~pg4
- restapi->connect_address
  - 根据各自节点IP设置
- postgresql->connect_address
  - 根据各自节点IP设置



启动patroni

在所有节点上启动patroni。

```
systemctl start patroni
```

同一个cluster中，第一次启动的patroni实例会作为leader运行，并初始创建PostgreSQL实例和用户。后续节点初次启动时从leader节点克隆数据



查看cn集群状态

```
[root@node1 ~]# patronictl -c /etc/patroni.yml list
+ Cluster: cn (6869267831456178056) +---------+----+-----------+-----------------+
| Member |       Host      |  Role  |  State  | TL | Lag in MB | Pending restart |
+--------+-----------------+--------+---------+----+-----------+-----------------+
|  pg1   | 192.168.234.201 |        | running |  1 |       0.0 |        *        |
|  pg2   | 192.168.234.202 | Leader | running |  1 |           |                 |
+--------+-----------------+--------+---------+----+-----------+-----------------+
```



查看wk1集群状态

```
[root@node3 ~]# patronictl -c /etc/patroni.yml list
+ Cluster: wk1 (6869267726994446390) ---------+----+-----------+-----------------+
| Member |       Host      |  Role  |  State  | TL | Lag in MB | Pending restart |
+--------+-----------------+--------+---------+----+-----------+-----------------+
|  pg3   | 192.168.234.203 |        | running |  1 |       0.0 |        *        |
|  pg4   | 192.168.234.204 | Leader | running |  1 |           |                 |
+--------+-----------------+--------+---------+----+-----------+-----------------+
```



为了方便日常操作，设置全局环境变量`PATRONICTL_CONFIG_FILE`

```
echo 'export PATRONICTL_CONFIG_FILE=/etc/patroni.yml' >/etc/profile.d/patroni.sh
```

添加以下环境变量到`~postgres/.bash_profile`，。

```
export PGDATA=/pgsql/data
export PATH=/usr/pgsql-12/bin:$PATH
```

设置postgres拥有sudoer权限

```
echo 'postgres        ALL=(ALL)       NOPASSWD: ALL'> /etc/sudoers.d/postgres
```



## 5.  配置Citus



在cn和wk的主节点上创建citus扩展

```
create extension citus
```



在cn的主节点上，添加wk1的主节点IP，groupid设置为1。

```
SELECT * from master_add_node('192.168.234.204', 5432, 1, 'primary');
```



在cn的主备节点上，创建`~postgres/.pgpass` 文件，支持CN免密连接Worker。

```
#hostname:port:database:username:password
192.168.234.203:5432:postgres:postgres:123456
192.168.234.204:5432:postgres:postgres:123456
```



创建分片表测试验证

```
create table tb1(id int primary key,c1 text);
set citus.shard_count = 64;
select create_distributed_table('tb1','id');
```



## 6. 配置Worker的自动流量切换

上面配置的Worker IP是当时的Worker主节点IP，在Worker发生主备切换后，这个IP将失效。

因此，需要通过脚本监视worker主备状态，当worker主备角色更新时，自动更新Citus上的worker元数据为新主节点的IP。下面是脚本的参考实现



创建配置文件`/pgsql/citus_controller.yml`

```
postgresql:
  connect_address: 192.168.234.202:5432
  authentication:
    superuser:
      username: postgres
      password: "123456"

citus:
  loop_wait: 10
  databases:
  - postgres

  workers:
  - groupid: 1
    nodes:
    - 192.168.234.203:5432
    - 192.168.234.204:5432
```

上面的`citus`节点也可以添加到'/etc/patroni.yml'里，这样可以共用部分配置。



创建worker流量自动切换脚本`/pgsql/citus_controller.py`

```
#!/usr/bin/env python2
# -*- coding: utf-8 -*-

import os
import time
import argparse
import logging
import yaml
import psycopg2


def get_pg_role(url):
    result = 'unknow'
    try:
        with psycopg2.connect(url, connect_timeout=2) as conn:
            conn.autocommit = True
            cur = conn.cursor()
            cur.execute("select pg_is_in_recovery()")
            row = cur.fetchone()
            if row[0] == True:
                result = 'secondary'
            elif row[0] == False:
                result = 'primary'
    except Exception as e:
        logging.debug('get_pg_role() failed. url:{0} error:{1}'.format(
                    url, str(e)))

    return result

def update_worker(url, role, groupid, nodename, nodeport):
    logging.debug('call update worker. role:{0} groupid:{1} nodename:{2} nodeport:{3}'.format(
                    role, groupid, nodename, nodeport))
    try:
        sql = "select nodeid,nodename,nodeport from pg_dist_node where groupid={0} and noderole = '{1}' order by nodeid limit 1".format(
                                                                        groupid, role)
        conn = psycopg2.connect(url, connect_timeout=2)
        conn.autocommit = True
        cur = conn.cursor()
        cur.execute(sql)
        row = cur.fetchone()
        if row is None:
            logging.error("can not found nodeid whose groupid={0} noderole = '{1}'".format(groupid, role))
            return False
        
        nodeid = row[0]
        oldnodename = row[1]
        oldnodeport = str(row[2])

        if oldnodename == nodename and oldnodeport == nodeport:
            logging.debug('skip for current nodename:nodeport is same')
            return False

        sql= "select master_update_node({0}, '{1}', {2})".format(nodeid, nodename, nodeport)
        ret = cur.execute(sql)
        logging.info("Changed worker node {0} from '{1}:{2}' to '{3}:{4}'".format(nodeid, oldnodename, oldnodeport, nodename, nodeport))
        return True
    except Exception as e:
        logging.error('update_worker() failed. role:{0} groupid:{1} nodename:{2} nodeport:{3} error:{4}'.format(
                    role, groupid, nodename, nodeport, str(e)))
        return False


def main():
    parser = argparse.ArgumentParser(description='Script to auto setup Citus worker')
    parser.add_argument('-c', '--config', default='citus_controller.yml')
    parser.add_argument('-d', '--debug', action='store_true', default=False)
    args = parser.parse_args()

    if args.debug:
        logging.basicConfig(format='%(asctime)s %(levelname)s: %(message)s', level=logging.DEBUG)
    else:
        logging.basicConfig(format='%(asctime)s %(levelname)s: %(message)s', level=logging.INFO)

    # read config file
    f = open(args.config,'r')
    contents = f.read()
    config = yaml.load(contents, Loader=yaml.FullLoader)

    cn_connect_address = config['postgresql']['connect_address']
    username = config['postgresql']['authentication']['superuser']['username']
    password = config['postgresql']['authentication']['superuser']['password']
    databases = config['citus']['databases']
    workers = config['citus']['workers']
    dbname = databases[0]

    loop_wait = config['citus'].get('loop_wait',10)
 
    logging.info('start main loop')
    loop_count = 0
    while True:
        loop_count += 1
        logging.debug("##### main loop start [{}] #####".format(loop_count))

        cn_url = "postgres://{0}/{1}?user={2}&password={3}".format(
                                    cn_connect_address,dbname,username,password)
        if(get_pg_role(cn_url) == 'primary'):
            for worker in workers:
                groupid = worker['groupid']
                nodes = worker['nodes']
    
                ## get role of worker nodes
                primarys = []
                secondarys = []
                for node in nodes:
                    wk_url = "postgres://{0}/{1}?user={2}&password={3}".format(
                                    node,dbname,username,password)
                    role = get_pg_role(wk_url)
                    if role == 'primary':
                        primarys.append(node) 
                    elif role == 'secondary':
                        secondarys.append(node) 
    
                logging.debug('Role info groupid:{0} primarys:{1} secondarys:{2}'.format(
                                        groupid,primarys,secondarys))

                ## update worker node
                for dbname in databases:
                    cn_url = "postgres://{0}/{1}?user={2}&password={3}".format(
                                        cn_connect_address,dbname,username,password)
                    if len(primarys) == 1:
                        nodename = primarys[0].split(':')[0]
                        nodeport = primarys[0].split(':')[1]
                        update_worker(cn_url, 'primary', groupid, nodename, nodeport)

                    """
                    Citus的pg_dist_node元数据中要求nodename:nodeport必须唯一，所以无法同时支持secondary节点的动态更新。
                    一个可能的回避方法是为每个worker配置2个IP地址，一个作为parimary角色时使用，另一个作为secondary角色时使用。

                    if len(secondarys) >= 1:
                        nodename = secondarys[0].split(':')[0]
                        nodeport = secondarys[0].split(':')[1]
                        update_worker(cn_url, 'secondary', groupid, nodename, nodeport)
                    elif len(secondarys) == 0 and len(primarys) == 1:
                        nodename = primarys[0].split(':')[0]
                        nodeport = primarys[0].split(':')[1]
                        update_worker(cn_url, 'secondary', groupid, nodename, nodeport)
                    """

        time.sleep(loop_wait)

if __name__ == '__main__':
    main()
```



再cn主备节点上都启动worker流量自动切换脚本

```
su - postgres
cd /pgsql
python citus_controller.py -c citus_controller.yml
```



## 7. 读写分离

根据上面的配置，Citus CN不会访问Worker的备机，这些备机闲着也是闲着，能否让Citus CN支持读写分离呢？也就是让CN的备机优先访问Worker的备机，Worker备节故障时访问Worker的主机。

Citus有读写分离功能，可以把一个worker的主备节点作为2个worker项目分别以`primary`和`secondary`的角色加入到同一个group里。但是，由于Citus的pg_dist_node元数据中要求nodename:nodeport必须唯一，所以前面的动态修改Citus元数据中的worker IP的方式无法同时支持primary节点和secondary节点的动态更新。

解决办法有2个

方法1：Citus元数据中只写固定的主机名，比如wk1，wk2...，然后通过自定义的worker流量自动切换脚本将这个固定的主机名解析成不同的IP地址写入到`/etc/hosts`里，也就是在CN主库上解析成Worker主库的IP，在CN备库上解析成Worker备库的IP。

方法2：在Worker上动态绑定读写VIP和只读VIP。在Citus元数据中读写VIP作为primary角色的Worker，只读VIP作为secondary角色的Worker。



patroni动态绑VIP的方法参考`基于patroni搭建PostgreSQL HA集群.md`

对Citus worker，读写VIP通过callback脚本动态绑定；只读VIP通过keepalived动态绑定。



采用这种方式时，创建Citus集群时，就需要把Worker的VIP加入集群。

在cn的主节点上，添加wk1的读写VIP(192.168.234.210)和只读VIP（192.168.234.211），groupid设置为1。

```
SELECT * from master_add_node('192.168.234.210', 5432, 1, 'primary');
SELECT * from master_add_node('192.168.234.211', 5432, 1, 'secondary');
```



在cn的主备节点上，创建`~postgres/.pgpass` 文件，支持CN免密连接Worker。

```
#hostname:port:database:username:password
192.168.234.210:5432:postgres:postgres:123456
192.168.234.211:5432:postgres:postgres:123456
```



为了让CN备库连接到secondary的worker，还需要再CN备库上设置以下参数

```
alter system set citus.use_secondary_nodes=always;
select pg_reload_conf();
```



现在分别到CN主库和备库上执行同一条SQL，可以看到SQL被发往不同的worker。

CN主库（未设置`citus.use_secondary_nodes=always`）：

```
postgres=# explain select * from tb1;
                                  QUERY PLAN
-------------------------------------------------------------------------------
 Custom Scan (Citus Adaptive)  (cost=0.00..0.00 rows=100000 width=36)
   Task Count: 32
   Tasks Shown: One of 32
   ->  Task
         Node: host=192.168.234.210 port=5432 dbname=postgres
         ->  Seq Scan on tb1_102168 tb1  (cost=0.00..22.70 rows=1270 width=36)
(6 rows)
```



CN备库（设置了`citus.use_secondary_nodes=always`）：

```
postgres=# explain select * from tb1;
                                  QUERY PLAN
-------------------------------------------------------------------------------
 Custom Scan (Citus Adaptive)  (cost=0.00..0.00 rows=100000 width=36)
   Task Count: 32
   Tasks Shown: One of 32
   ->  Task
         Node: host=192.168.234.211 port=5432 dbname=postgres
         ->  Seq Scan on tb1_102168 tb1  (cost=0.00..22.70 rows=1270 width=36)
(6 rows)
```



由于CN也会发生主备切换，上面这个参数必须动态调节。这可以使用patroni的回调脚本实现



创建动态设置参数的`/pgsql/switch_use_secondary_nodes.sh`

```
#!/bin/bash

DBNAME=postgres

action=$1
role=$2
cluster=$3


log()
{
  echo "switch_use_secondary_nodes: $*"|logger
}

alter_use_secondary_nodes()
{
  value="$1"
  psql -d ${DBNAME} -c "alter system set citus.use_secondary_nodes=${value}"
  rc=$?
  if [ $rc -ne 0 ] ;then
    log "fail to alter use_secondary_nodes to '${value}' rc=$rc"
    exit 1
  fi

  psql -d ${DBNAME} -c 'select pg_reload_conf()'
  rc=$?
  if [ $rc -ne 0 ] ;then
    log "fail to call pg_reload_conf() rc=$rc"
    exit 1
  fi

  log "alter use_secondary_nodes to '${value}'"
}

log "switch_use_secondary_nodes start args:'$*'"

case $action in
  on_start|on_restart|on_role_change)
    case $role in
      master)
        alter_use_secondary_nodes never
        ;;
      replica)
        alter_use_secondary_nodes always
        ;;
      *)
        log "wrong role '$role'"
        exit 1
        ;;
    esac
    ;;
  *)
    log "wrong action '$action'"
    exit 1
    ;;
esac

```



修改patroni配置文件`/etc/patroni.yml`，配置回调函数

```
postgresql:
...

  callbacks:
    on_start: /bin/bash /pgsql/switch_use_secondary_nodes.sh
    on_restart: /bin/bash /pgsql/switch_use_secondary_nodes.sh
    on_role_change: /bin/bash /pgsql/switch_use_secondary_nodes.sh

```

所有节点的patroni配置文件都修改后，重新加载patroni配置

```
patronictl reload pgsql
```

cn上执行switchover后，可以看到`use_secondary_nodes`发生了切换

/var/log/messages:

```
Sep  7 02:27:17 node1 postgres: switch_use_secondary_nodes: switch_use_secondary_nodes start args:'on_role_change replica cn'
Sep  7 02:27:17 node1 patroni: ALTER SYSTEM
Sep  7 02:27:17 node1 patroni: pg_reload_conf
Sep  7 02:27:17 node1 patroni: ----------------
Sep  7 02:27:17 node1 patroni: t
Sep  7 02:27:17 node1 patroni: (1 行记录)
Sep  7 02:27:17 node1 postgres: switch_use_secondary_nodes: alter use_secondary_nodes to 'always'
```





### 8. 参考

- [基于Patroni的PostgreSQL高可用环境部署.md](https://github.com/ChenHuajun/chenhuajun.github.io/blob/master/_posts/2020-09-07-基于Patroni的PostgreSQL高可用环境部署.md)
- 《基于*Patroni*的*Citus*高可用方案》（PostgreSQL中国用户大会2019分享主题）
- https://patroni.readthedocs.io/en/latest/
- http://blogs.sungeek.net/unixwiz/2018/09/02/centos-7-postgresql-10-patroni/
- https://scalegrid.io/blog/managing-high-availability-in-postgresql-part-1/
- https://jdbc.postgresql.org/documentation/head/connect.html#connection-parameters
- https://www.percona.com/blog/2019/10/23/seamless-application-failover-using-libpq-features-in-postgresql/