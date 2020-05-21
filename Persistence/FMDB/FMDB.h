#import <Foundation/Foundation.h>

FOUNDATION_EXPORT double FMDBVersionNumber;
FOUNDATION_EXPORT const unsigned char FMDBVersionString[];

#import "FMDatabase.h"
#import "FMResultSet.h"
#import "FMDatabaseAdditions.h"
#import "FMDatabaseQueue.h"
#import "FMDatabasePool.h"

/**
 * FMDatabase：代表一个单独的SQLite操作实例，数据库通过它增删改查操作，以及事务和SavePoint、checkpoint 等；
 * FMResultSet：代表查询后的结果集，可以通过它遍历查询的结果集，获取出查询得到的数据；
 * FMDatabaseQueue：代表串行队列，对多线程操作提供了支持，保证多线程环境下的数据安全；
 * FMDatabaseAdditions：是FMDatabase的分类，扩展了查找表是否存在，版本号，表信息等功能；
 * FMDatabasePool：FMDatabase的对象池封装，在多线程环境中访问单个FMDatabase对象容易引起问题，可以通过FMDatabasePool对象池来解决多线程下的访问安全问题；不推荐使用，优先使用FMDatabaseQueue。
 */


/*
  
 
 以下两个对象和八个方法构成了 SQLite3 接口的基本元素：

 sqlite3 ：数据库连接对象。通过 sqlite3_open() 创建 ，并通过 sqlite3_close() 释放。

 sqlite3_stmt : 准备好的语句对象。通过 sqlite3_prepare() 创建，并通过 sqlite3_finalize() 释放。

 sqlite3_open() ：打开与新的或现有的SQLite3数据库的连接。sqlite3的构造函数。

 sqlite3_prepare() ：将SQL文本编译为字节代码，它将完成查询或更新数据库的工作。sqlite3_stmt的构造函数。

 sqlite3_bind() ：将应用程序数据存储到 原始SQL的参数中。

 sqlite3_step() ：将 sqlite3_stmt前进到下一个结果行或完成。

 sqlite3_column()当前结果行用于在→列值 sqlite3_stmt。

 sqlite3_finalize() ： sqlite3_stmt的析构函数。

 sqlite3_close() ： sqlite3的析构函数。

 sqlite3_exec() ： 一个包装函数，对一个或多个SQL语句字符串执行 sqlite3_prepare()， sqlite3_step()， sqlite3_column()和 sqlite3_finalize()。
 
 */
