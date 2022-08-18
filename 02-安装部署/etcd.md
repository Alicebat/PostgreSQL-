# 版本
Versions : 3.3

语言：go  (golang)

## 3 服务器管理

### 3.2 ETCD configure
#### 3.2.1 发展现状

*   https://github.com/etcd-io/etcd/issues?page=2&q=is%3Aissue+is%3Aopen
*   https://etcd.io/docs/v3.3/faq/

#### 3.2.2 常用操作
etcdctl

*   version: 查看版本
*   member list: 查看节点状态，learner 情况
*   endpoint status: 节点状态，leader 情况
*   endpoint health: 健康状态与耗时
*   alarm list: 查看警告，如存储满时会切换为只读，产生 alarm
*   alarm disarm：清除所有警告
*   set app demo: 写入
*   get app: 获取
*   update app demo1:更新
*   rm app: 删除
*   mkdir demo 创建文件夹
*   rmdir dir 删除文件夹
*   backup 备份
*   compaction： 压缩
*   defrag：整理碎片
*   watch key 监测 key 变化
*   get / --prefix --keys-only: 查看所有 key
*   --write-out= tables，可以用表格形式输出更清晰，注意有些输出并不支持tables
```
etcd+patroni 集群信息存放目录
[root@cluster_vastbase_1 etcd-v3.3.18-linux-amd64]# ./etcdctl ls /service/vastbase_cluster
/service/vastbase_cluster/failover
/service/vastbase_cluster/members  #各个成员API连接信息
/service/vastbase_cluster/initialize   # 显示集群是否有初始化键
/service/vastbase_cluster/leader     #存放patroni集群leader信息
/service/vastbase_cluster/config     #存放patroni数据库配置信息
/service/vastbase_cluster/optime   # 最后一个已知leader操作的位置
```

#### 3.2.2 集群配置
编辑ETCD配置文件，各个节点根据实际情况编写，ETCD数据目录建议放到固态硬盘下，请务必注意
```
vi ${ANY_PATH}/dcs_conf.yml
name: etcd1
data-dir: /data/etcd              # ETCD数据目录
initial-advertise-peer-urls: http://172.16.101.101:2380
listen-peer-urls: http://172.16.101.101:2380
listen-client-urls: http://172.16.101.101:2379,http://127.0.0.1:2379
advertise-client-urls: http://172.16.101.101:2379
initial-cluster-token: etcd-cluster-vastbase
initial-cluster: etcd1=http://172.16.101.101:2380,etcd2=http://172.16.101.102:2380,etcd3=http://172.16.101.103:2380
enable-v2: true
initial-cluster-state: new
```
IPv6配置注意事项：

1.DCS配置中所有的IP地址需要添加方括号；
*   示例：当前节点ip为2001::e1:172:16:103:88，配置文件如下
![Image text](./_media/etcd_ipv6_1.png)

2.使用命令时需要指定 --endpoints的值；
*   示例：当前节点ip为2001::e1:172:16:103:88，使用本地ip为 ::1 ；
![Image text](./_media/etcd_ipv6_2.png)


#### 3.2.3 etcd system 配置
编辑DCS服务配置文件，${ETCD_PATH} 为ETCD安装目录，请根据实际情况填写
```
vi /usr/lib/systemd/system/dcs.service
[Unit]
Description=Vastbase DCS server daemon
After=network.target

[Install]
WantedBy=multi-user.target

[Service]
Type=notify
EnvironmentFile=-/etc/sysconfig/vastbase-dcs
ExecStart=${ETCD_PATH}/etcd $CONFIG_FILE 
Restart=no
```
编辑DCS服务环境变量文件，${ANY_PATH}/dcs_conf.yml为步骤3.4.2中编写的配置文件，请务必注意
```
vi /etc/sysconfig/vastbase-dcs
ETCD_UNSUPPORTED_ARCH=arm64      # ARM平台才需要，x86不需要
CONFIG_FILE=--config-file  ${ANY_PATH}/dcs_conf.yml
```

#### 3.2.4 etcd图形化管理工具
etcd服务搭建完成后，里面其实存储了很多的key，如何查看和管理这些key，需要使用一个小工具，叫做etcdkeeper
etcd节点选一台部署：
```
cd /opt/;wget https://github.com/evildecay/etcdkeeper/releases/download/v0.7.6/etcdkeeper-v0.7.6-linux_x86_64.zip
unzip etcdkeeper-v0.7.6-linux_x86_64.zip;cd etcdkeeper;chmod +x etcdkeeper
```
*   编写开机启动文件：
```
vim /usr/lib/systemd/system/etcdkeeper.service


[Unit]
Description=etcdkeeper service
After=network.target
[Service]
Type=simple
ExecStart=/opt/etcdkeeper/etcdkeeper -h 192.168.52.38 -p 8800 #监听ip和端口自定义 不要跟k8s组件的端口冲突
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
Restart=on-failure
PrivateTmp=true
[Install]
WantedBy=multi-user.target
```
*   开机启动
```
systemctl enable etcdkeeper.service
```
*   启动服务
```
systemctl start etcdkeeper
```
浏览器打开地址：http://192.168.52.38:8800/etcdkeeper/
