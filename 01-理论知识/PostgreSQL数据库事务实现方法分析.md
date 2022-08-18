## PostgreSQL数据库事务实现方法分析
### 1.事务简介
*   事务管理器：有限状态
    *   日志管理器
        CLOG：事务的执行结果
        XLOG：undo/redo日志
    *   锁管理器：实现并发控制，读阶段采用MVCC，写阶段采用锁控制实现不同的隔离级别


事务是所有数据库系统的一个基本概念。 一次事务的要点就是它把多个步骤捆绑成了一个单一的，不成功则成仁的操作。 其它并发的事务是看不到在这些步骤之间的中间状态的，并且如果发生了一些问题， 导致该事务无法完成，那么所有这些步骤都完全不会影响数据库。PostgreSQL为每条事务创建一个postgre进程，并发执行事务。采用分层的机制执行事务，上层事务块和底层事务。上层事务块是用户眼中的事务，用于控制事务执行的状态；底层事务是事务中的每条语句，可以改变上层事务块的状态。

*   上层事务块

每个postgre进程只有一个事务块，上层事务块记录着本次事务执行过程中的各个状态。
```
typedef enum TBlockState
{
  /* not-in-transaction-block states */
  TBLOCK_DEFAULT,       /* idle */
  TBLOCK_STARTED,       /* 执行简单查询事务 */
  /* transaction block states */
  TBLOCK_BEGIN,        /* 遇见事务开始BEGIN */
  TBLOCK_INPROGRESS,     /* 事务正在执行中 */
  TBLOCK_PARALLEL_INPROGRESS, /* live transaction inside parallel worker */
  TBLOCK_END,         /* 遇见事务结束COMMIT/END的时候设置 */
  TBLOCK_ABORT,        /* 事务出错，等待ROLLBACK */
  TBLOCK_ABORT_END,      /* 事务出错，收到ROLLBACK */
  TBLOCK_ABORT_PENDING,    /* 事务处理中，接收到ROLLBACK */
  TBLOCK_PREPARE,       /* 事务处理中，收到PREPARE(分布式事务) */
  /* subtransaction states */
  TBLOCK_SUBBEGIN,      /* starting a subtransaction */
  TBLOCK_SUBINPROGRESS,    /* live subtransaction */
  TBLOCK_SUBRELEASE,     /* RELEASE received */
  TBLOCK_SUBCOMMIT,      /* COMMIT received while TBLOCK_SUBINPROGRESS */
  TBLOCK_SUBABORT,      /* failed subxact, awaiting ROLLBACK */
  TBLOCK_SUBABORT_END,    /* failed subxact, ROLLBACK received */
  TBLOCK_SUBABORT_PENDING,  /* live subxact, ROLLBACK received */
  TBLOCK_SUBRESTART,     /* live subxact, ROLLBACK TO received */
  TBLOCK_SUBABORT_RESTART   /* failed subxact, ROLLBACK TO received */
} TBlockState;
```
常见的事务块状态转换图

![Image text](./_media/企业微信截图_16519792212812.png)

* startTransactionCommand：事务块中每条语句执行前都会调用。
* commitTransactionCommand：事务块中每条语句执行结束都会调用
* abortCurrentTransaction：事务块中语句执行错误，在调用点调用
* BeginTransactionBlock：遇见BEGIN命令调用，状态变为TBLOCK_BEGIN
* EndTransactionBlock：遇见END调用，可能成功提交，也可能回滚
* AbortTransactionBlock：遇见ABORT指令调用

* 底层事务

底层事务是需要执行的每条命令，负责处理资源和锁的获取和释放，信号的处理，日志记录等等
```
typedef enum TransState
{
  TRANS_DEFAULT,       /* idle */
  TRANS_START,        /* transaction starting */
  TRANS_INPROGRESS,      /* inside a valid transaction */
  TRANS_COMMIT,        /* commit in progress */
  TRANS_ABORT,        /* abort in progress */
  TRANS_PREPARE        /* prepare in progress */
} TransState;
```

主要有四个函数：

* StartTransaction：由BEGIN的startTransactionCommand调用，调用结束后事务块状态为TBLOCK_STARTED
* CommitTransaction：由END的commitTransactionCommand调用，提交事务
* AbortTransaction和CleanupTransaction：释放资源，恢复默认状态

分布式事务

PostgreSQL提供了分布式事务中的，两阶段提交的接口

并发控制

PostgreSQL采用MVCC的方式进行并发控制，每个事务看到的是一段时间前的数据快照。同时，MVCC并不能够解决所有问题，所以也提供了行级和表级的锁。

标准的事务隔离级别有4个，而PostgreSQL只实现了读已提交和可串行化。

锁
PostgreSQL实现了8种锁(可怕)
![Image text](./_media/2018822120116899.png)

加锁的对象

*   表
    *   表锁
    *   会话锁
    *   扩展锁：新增表空间
*   页：对索引页面
*   元组：
*   事务：
死锁处理
![Image text](./_media/2018822120307204.png)
postgresql检测出最后一个等待的杀掉，oracle是第一个等待的杀掉
死锁检测算法(等待图)

MVCC
关键词：

*   基于事务ID
*   行级多版本
*   无回滚段，行内存储
    *   一次UPDATE，产生记录两个版本
    *   两个版本都存在页面内部

```
typedef struct HeapTupleFields
{
  TransactionId t_xmin;    /* Insert，Update事务 */
  TransactionId t_xmax;    /* Delete，Update，Row Locks事务ID */
  union
  {
    CommandId  t_cid;   /* 操作ID */
    TransactionId t_xvac;  /* old-style VACUUM FULL xact ID */
  }      t_field3;
} HeapTupleFields;
```

cmin:插入该元组的命令在插入事务中的命令标识（从0开始累加）
cmax:删除该元组的命令在插入事务中的命令标识（从0开始累加）
ctid：相当于rowid ， <数据块ID，偏移量>
XID:事务ID
Xid_snapshot:当前系统中未提交的事务
CLOG：事务状态日志(已提交的日志)


日志

    1.  pg_log:数据库活动日志（也就是数据库的操作日志）；
    2.  pg_xlog:事务日志，记录事务的执行过程，redo日志
    3.  pg_clog:事务状态日志（pg_clog是pg_xlog的辅助日志），记录事务的结果。