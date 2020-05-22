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
 
 
  
 ####2、SQLite 函数

 [SQLite 函数](https://www.sqlite.org/cintro.html) 提供了对数据库的操作！

 

 Sql 处理为 sqlite3_stmt
 执行 sqlite3_stmt


  1
  sqlite3_open(const char *filename, sqlite3 **ppDb)
  该例程打开一个指向 SQLite 数据库文件的连接，返回一个用于其他 SQLite 程序的数据库连接对象。
  如果 filename 参数是 NULL 或 ':memory:'，那么 sqlite3_open() 将会在 RAM 中创建一个内存数据库，这只会在 session 的有效时间内持续。
  如果文件名 filename 不为 NULL，那么 sqlite3_open() 将使用这个参数值尝试打开数据库文件。如果该名称的文件不存在，sqlite3_open() 将创建一个新的命名为该名称的数据库文件并打开。
  
  
  2
  sqlite3_exec(sqlite3*, const char *sql, sqlite_callback, void *data, char **errmsg)
  该例程提供了一个执行 SQL 命令的快捷方式，SQL 命令由 sql 参数提供，可以由多个 SQL 命令组成。
  在这里，第一个参数 sqlite3 是打开的数据库对象，sqlite_callback 是一个回调，data 作为其第一个参数，errmsg 将被返回用来获取程序生成的任何错误。
  sqlite3_exec() 程序解析并执行由 sql 参数所给的每个命令，直到字符串结束或者遇到错误为止。
  
  3
  sqlite3_close(sqlite3*)
  该例程关闭之前调用 sqlite3_open() 打开的数据库连接。所有与连接相关的语句都应在连接关闭之前完成。
  如果还有查询没有完成，sqlite3_close() 将返回 SQLITE_BUSY 禁止关闭的错误消息。
  
  
  
sqlite_version() 函数返回 SQLite 库的版本。


 
 
 以下两个对象和八个方法构成了 SQLite3 接口的基本元素：

 sqlite3 ：数据库连接对象。通过 sqlite3_open() 创建 ，并通过 sqlite3_close() 释放。

 sqlite3_stmt : 预处理语句对象。通过 sqlite3_prepare() 创建，并通过 sqlite3_finalize() 释放。

 sqlite3_open() ：打开与新的或现有的SQLite3数据库的连接，是sqlite3的构造函数。
 sqlite3_close() ： sqlite3的析构函数。
 
 sqlite3_prepare() ：sqlite3_stmt的构造函数，将SQL文本编译为字节代码，它将完成查询或更新数据库的工作。
 sqlite3_finalize() ： sqlite3_stmt的析构函数。
 
 
 sqlite3_bind_*() ：将应用程序数据存储到 原始SQL的参数中。

 sqlite3_step() ：将 sqlite3_stmt 前进到下一个结果或完成。

 sqlite3_column() 当前结果行用于在→列值 sqlite3_stmt。

 sqlite3_exec() ： 一个包装函数，对一个或多个SQL语句字符串执行 sqlite3_prepare()， sqlite3_step()， sqlite3_column()和 sqlite3_finalize()。
 
 */
