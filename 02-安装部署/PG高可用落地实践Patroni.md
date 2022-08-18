# PG高可用落地实践:Patroni

https://github.com/Vonng/pigsty

## 大纲

* 意义

* 目标

* 效果

* 接口

* 问题与风险

  

  



## 一、意义

1. 显著提高系统整体可用性，提高RTO与RPO水平。
2. 极大提高运维灵活性与可演化性，可以通过主动切换进行滚动升级，灰度停机维护。
3. 极大提高系统可维护性，自动维护域名，服务，角色，机器，监控等系统间的一致性。显著减少运维工作量，降低管理成本



## 二、目标

当我们在说高可用时，究竟在说什么？Several nines ?

说到底，对于传统单领导者数据库来说，**核心问题是就是故障切换，是领导权力交接的问题。**

#### 目标层次

* L0，手工操作，完全通过DBA人工介入，手工操作完成故障切换（十几分钟到小时级）
* L1，辅助操作，有一系列手工脚本，完成选主，拓扑切换，流量切换等操作（几分钟）
* L2，半自动化，自动检测，人工决策，自动操作。（1分钟）
* L3，全自动化：自动检测，自动决策，自动操作。（10s）

#### 关键指标

* 允许进行日常Failover与Switchover操作，不允许出现脑裂。
* 无需客户端介入，提供代理切换机制，基于流复制，不依赖特殊硬件。
* 域名解析，VIP流量切换，服务发现，监控适配都需要与自动故障切换对接，做到自动化。
* 支持PG 10～12版本与CentOS 7，不会给云原生改造埋坑。

#### 交付方式

* 沙盒模型，展示期待的部署架构与状态
* 调整方案，说明如何将现有环境调整至理想状态。



## 三、效果

#### 场景演示

集群状况介绍

* 主库URL：`postgres://dbuser_test:dbuser_test@testdb:5555/testdb`
* 从库URL：`postgres://dbuser_test:dbuser_test@testdb:5556/testdb`

HA的两个核心场景：

* Switchover演示
* Failover演示

故障切换的四个核心问题：

* 故障检测（Lease, TTL，Patroni向DCS获取Leader Key）
* Fencing（Patroni demote，kill PG进程，或通过Watchdog直接重启）
* 拓扑调整（通过DCS选主，其他从库从DCS获取新主库信息，修改自身复制源并重启生效）
* 流量切换（监听选主事件，通知网络层修改解析）

![architecture](/Users/vonng/Documents/img/architecture.png)

### Patroni原理：故障检测

* 基于DCS判定
* 心跳包保活
* Leader Key Lease
* 秦失其鹿，天下共逐之。

### Patroni原理：Fencing

* 一山不容二虎，成王败寇，血腥的权力交接。

### Patroni原理：选主

* The king is dead, long live the king
* 先入关者王

### 流量切换原理

* 回调事件，或监听DCS变化。



## 搭建环境

https://github.com/Vonng/pigsty/tree/master/ansible



## 五、细节，问题，与风险

### 场景演示

* Switchover
* Standby Down
  * Patroni Down
  * Postgres Down
  * Accidentally Promote
* Primary Down
* Failover
* DCS Down
  * DCS Service Down
  * DCS Primary Client Down
  * DCS Standby Client Down
* Fencing And corner cases
* Standby Cluster
* Sync Standby
* Takeover existing cluster



### 问题探讨

**关键问题：DCS的SLA如何保障？**

**==在自动切换模式下，如果DCS挂了，当前主库会在retry_timeout 后Demote成从库，导致所有集群不可写==。**

作为分布式共识数据库，Consul/Etcd是相当稳健的，但仍必须确保DCS的SLA高于DB的SLA。

解决方法：配置一个足够大的`retry_timeout`，并通过几种以下方式从管理上解决此问题。

1. SLA确保DCS一年的不可用时间短于该时长
2. 运维人员能确保在`retry_timeout`之内解决DCS Service Down的问题。
3. DBA能确保在`retry_timeout`之内将关闭集群的自动切换功能（打开维护模式）。

> **可以优化的点？** 添加绕开DCS的P2P检测，如果主库意识到自己所处的分区仍为Major分区，不触发操作。



**关键问题：HA策略，RPO优先或RTO优先？**

可用性与一致性谁优先？例如，普通库RTO优先，金融支付类RPO优先。

普通库允许紧急故障切换时丢失极少量数据（阈值可配置，例如最近1M写入）

与钱相关的库不允许丢数据，相应地在故障切换时需要更多更审慎的检查或人工介入。



**关键问题：Fencing机制，是否允许关机？**

在正常情况下，Patroni会在发生Leader Change时先执行Primary Fencing，通过杀掉PG进程的方式进行。

但在某些极端情况下，比如vm暂停，软件Bug，或者极高负载，有可能没法成功完成这一点。那么就需要通过重启机器的方式一了百了。是否可以接受？在极端环境下会有怎样的表现？



**关键操作：选主之后**

选主之后要记得存盘。手工做一次Checkpoint确保万无一失。



**关键问题：流量切换怎样做，2层，4层，7层**

* 2层：VIP漂移
* 4层：Haproxy分发
* 7层：DNS域名解析



**关键问题：一主一从的特殊场景**

* 2层：VIP漂移
* 4层：Haproxy分发
* 7层：DNS域名解析









## 四、接口

接口描述了外部视角所期待的系统状态。

### 基本概念

![ha-cluster-er](/Users/vonng/Documents/img/ha-cluster-er.png)

在Postgres集群管理中，有如下概念：

* **Cluster**：一个数据库集簇，包含一台或多个内容相同的实例，共同组成一个基础业务服务单元。

  每个集群都有自己的唯一标识符，本例中定义了一个名为`testdb`的数据库集群。

* **Service**：一个数据库服务，同一个数据集簇中通常包括主库与从库，两者分别提供读写服务（primary）和只读副本服务(standby)。

* **Instance**：一个具体的数据库服务器实例，同一个数据库服务，例如只读副本服务可能包含多个实例。

  实例隶属于集群，每个实例在集群范围内都有着自己的唯一序号用于区分。

* **Node**：一台机器，通常使用`lan_ip`地址作为唯一标识符，如果采用单实例部署，那么也可以使用实例的名称作为Node的Hostname，用作唯一标识。

* **解析**：将服务解析到对应实例地址的过程。

* **中控机**：用于控制管理其他数据库节点的机器，能够通过SSH访问其他机器。

* **DCS**：分布式共识数据库，例如consul，etcd，zookeeper，用于元数据存储，服务发现，配置管理，选主等。

名之必可言也，言之必可行也。最重要的接口是标识符命名规则，尽管每一个Node都可以通过`lan_ip`进行唯一标识，每一个服务实例也可以通过`lan_ip:port`的方式唯一标识，但对于管理而言还是需要一个带有逻辑意义的名称。

**Cluster命名规则**

Cluster是一个自治业务单元，需要一个唯一标识符`${cluster}`，例如`testdb`,`user-redis`, `usercenter`。

其命名应当是符合DNS规范的标识符，最好不要带`.`影响服务解析。

**Node命名规则**

Node的名称会在集群资源分配阶段确定下来，每个节点都会分配到一个序号`${seq}`，从1开始的自增整型，后缀以集群名称`${cluster}`规则为`${seq}.${cluster}`。

节点名称会作为机器的Hostname，在整个集群生命周期中保持不变。

本例中有三台机器，其序号分别为1,2,3，则其分别为`1.testdb`, `2.testdb`, `3.testdb`。

**Instance命名规则**

PG实例与Node是一一对应的关系，因此可以简单地采用Node的标识符作为Instance的标识符。

例如，机器`1.testdb`上的PG实例名即为：`1.testdb`，以此类推。

> 题外话，对于单机多实例的情况，另一种命名方式是把节点的逻辑序号和服务的端口号作为实例的标号。
>
> 例如假设所有服务端口都是四位数，则可以使用这种实例命名规则：
>
> `str( int(${node_seq}) * 10000 + int(${instance_port})).${cluster}`
>
> 例如在`2.testdb`机器上端口为6379的实例可以命名为`26379.testdb`。

**服务命名规则**

服务的命名规则是：`${role}.${cluster}`，例如`primary.testdb`和`standby.testdb`



### **应用层接口**

应用层通过且必须通过自动发现的服务域名`primary|standby|offline.$cluster`来访问数据库集群。

* 访问域名`primary.$cluster`，将自动连接至集群`$cluster`的主库。 

* 访问域名`standby.$cluster`，将自动连接至集群`$cluster`的主库。 

* 发生故障切换时，`(primary|standby).$cluster`短暂不可用，并在切换完成后自动恢复



### **系统层接口**

**机器角色域名**

对系统层（运维）来说，交付数据库机器时，不再区分`primary|standby`服务，而以自增整型前缀区分。

即，假定有集群名为`testdb1.tt`，交付三台机器，则其角色域名与机器一一绑定，并在整个业务生命周期中保持不变。

```ini
1.testdb1.tt
2.testdb1.tt
3.testdb1.tt
```

**服务域名动态解析**

此外，系统层需要提供以下两个域名的动态解析服务：

```bash
primary.testdb1.tt
standby.testdb1.tt
```

DB层会在发生切换时，通过回掉脚本，Webhook，或者提供DCS监听Key的方式通知系统层进行解析变更。

**Fencing权限**

是否允许高可用程序自动重启机器？

**高可用DCS服务**

最后，系统层提供专用的DCS服务，例如Consul或者Etcd，并确保其SLA应当高于数据库的SLA。



### **平台层接口**

因为现在主从角色随时可能发生变化，平台与数据库交互时，通过服务发现而非配置写死的方式管理对接数据库服务。例如对于名为`testdb1.tt`的数据库集群，服务发现的方式如下：

| service                                                      | port | tags                     | meta          |
| :----------------------------------------------------------- | ---- | :----------------------- | ------------- |
| [node_exporter](http://c.pigsty/ui/pigsty/services/node_exporter) | 9100 | exporter                 | type=exporter |
| shannon_exporter                                             | 9101 | exporter                 | type=exporter |
| [pg_exporter](http://c.pigsty/ui/pigsty/services/pg_exporter) | 9630 | exporter                 | type=exporter |
| [pgbouncer_exporter](http://c.pigsty/ui/pigsty/services/pgbouncer_exporter) | 9631 | exporter                 | type=exporter |
| [patroni](http://c.pigsty/ui/pigsty/services/patroni)        | 8008 | primary  testdb  standby | type=patroni  |
| [pgbouncer](http://c.pigsty/ui/pigsty/services/pgbouncer)    | 6432 | primary  testdb  standby | type=postgres |
| [postgres](http://c.pigsty/ui/pigsty/services/postgres)      | 5432 | primary  testdb  standby | type=postgres |
| [testdb](http://c.pigsty/ui/pigsty/services/testdb)          | 5432 | primary standby 1 2 3    | type=db       |

平台层可以使用任何标签或元数据对相关服务进行筛选发现。例如平台监控可以通过`tags=exporter`筛选出所有监控端点。可以通过`__meta_consul_service_metadata_type=db`筛选出业务实际使用的DB服务。





### 切换流程细节

> #### 主动切换流程
>
> 假设集群包括一台主库P，n台从库S，所有从库直接挂载在主库上。
>
> - 检测：主动切换不需要检测故障
> - 选主：人工从集群中选择复制延迟最低的从库，将其作为候选主库(C)andidate。
> - 拓扑调整
>   - 修改主库P配置，使得C成为同步从库，使切换RTO = 0。
>   - 重定向其他从库，将其`primary_conninfo`指向C，作为级连从库，滚动重启生效。
> - 流量切换：需要快速自动化执行以下步骤
>   - Fencing P，停止当前主库P，视流量来源决定手段狠辣程度
>     - PAUSE Pgbouncer连接池
>     - 修改P的HBA文件并Reload
>     - 停止Postgres服务。
>     - 确认无法写入
>   - Promote C：提升候选主库C为新主库
>     - 移除standby.signal 或 recovery.conf。执行promote
>     - 如果Promote失败，重启P完成回滚。
>     - 如果Promote成功，执行以下任务：
>     - 自动生成候选主库C的新角色域名：`.primary.`
>     - 调整集群主库域名/VIP解析：`primary.` ，指向C
>     - 调整集群从库域名/VIP解析：`standby.`，摘除C（一主一从除外）
>     - 根据新的角色域名重置监控（修改Consul Node名称并重启）
>   - Rewind P：（可选）将旧主库Rewind后作为新从库
>     - 运行`pg_rewind`，如果成功则继续，如果失败则直接重做从库。
>     - 修改`recovery.conf(12-)|postgresql.auto.conf(12)`，将其`primary_conninfo`指向C
>     - 自动生成P的新角色域名：`< max(standby_sequence) + 1>.standby.`
>     - 集群从库域名/VIP解析变更：`standby.`，向S中添加P，承接读流量
>     - 根据角色域名重置监控
>
> #### 自动切换流程
>
> 自动切换的核心区别在于主库不可用。如果主库可用，那么完全同主动切换一样即可。
>
> 自动切换相比之下要多了两个问题，即检测与选主的问题，同时拓扑调整也因为主库不可用而有所区别。
>
> - 检测
>
>   - 策略：自动检测主库失效，需要监控系统作为基础，设定审慎的判定条件，以免频繁触发。应当采纳多个指标，同时考虑网络层，系统层，应用层的可用性，并从主库，从库，以及多个仲裁者的角度进行综合判定。
>
>     （网络不可达，端口拒绝连接，进程消失，无法写入，多个从库上的WAL Receiver断开）
>
>   - 实现：检测可以使用主动/定时脚本，也可以直接访问`pg_exporter`，或者由Agent定期向DCS汇报。
>
>   - 触发：主动式检测触发，或监听DCS事件。触发结果可以是调用中控机上的HA脚本进行集中式调整，也可以由Agent进行本机操作。
>
> - 选主
>
>   - 自动选主有一些微妙的地方，必须先确保主库P已经被Fencing才可以进行。否则复制延迟的变化因素太多，可能选完主之后，实际执行拓扑调整的时候，选出来的C已经不是复制延迟最低的那个了。
>   - Fencing P：同手动切换，因为自动切换中主库不可用，无法修改同步提交配置，因此存在RPO > 0 的可能性。
>   - 遍历所有可达从库，找出LSN最大者，选定为C，最小化RPO。
>
> 这里根据客户端对数据一致性C和服务可用性A的要求，又可以分为两种策略，追求数据一致性，则先完成拓扑调整，将所有其他从库挂载到C上之后再切换流量。如果追求可用性，保证最终一致性，容许短暂的读延迟（从库还没有全部挂载到C上，效果等同于复制延迟），则可以先立即切换流量，然后调整拓扑。这里假定客户端容许短暂的读取延迟，则为了尽可能快的恢复写入，应当在选主后立刻Promote，而不是等待并确认其他从库已经成功挂载。
>
> - 流量切换：需要快速自动化执行以下步骤
>
>   - Promote C：提升候选主库C为新主库
>     - 移除standby.signal 或 recovery.conf。执行promote
>     - 自动生成候选主库C的新角色域名：`.primary.`
>     - 调整集群主库域名/VIP解析：`primary.` ，指向C
>     - 调整集群从库域名/VIP解析：`standby.`，摘除C（一主一从除外）
>     - 根据新的角色域名重置监控（修改Consul Node名称并重启）
>
> - 拓扑调整
>
>   - 重定向其他从库，将其`primary_conninfo`指向C，作为级连从库，滚动重启生效，并追赶新主库C。
>   - 如果使用一主一从，之前C仍然承接读流量，则拓扑调整完成后将C摘除。
>
> - 修复旧主库P（如果是一主一从配置且读写负载单台C撑不住，则需要立刻进行，否则这一步不紧急）
>
>   - 修复有以下两种方式：Rewind，Remake
>   - Rewind P：（可选）将旧主库Rewind后作为新从库（如果只有一主一从则是必选）
>     - 运行`pg_rewind`，如果成功则继续，如果失败则直接重做从库。
>     - 修改`recovery.conf(12-)|postgresql.auto.conf(12)`，将其`primary_conninfo`指向C
>     - 自动生成P的新角色域名：`< max(standby_sequence) + 1>.standby.`
>     - 集群从库域名/VIP解析变更：`standby.`，向S中添加P，承接读流量
>     - 根据角色域名重置监控
>
>   - Remake P：
>     - 以新角色域名`< max(standby_sequence) + 1>.standby.`向集群添加新从库。
>
> 


