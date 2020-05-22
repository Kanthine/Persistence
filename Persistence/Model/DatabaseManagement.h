//
//  DatabaseManagement.h
//  Persistence
//
//  Created by 苏沫离 on 2018/4/24.
//  Copyright © 2018 苏沫离. All rights reserved.
//

#define MAX_STORE_TIME 7 * 24 * 60 * 60 //缓存数据最大有效期

#import <Foundation/Foundation.h>
#import "FMDatabase.h"
#import "FMResultSet.h"
#import "FMDatabaseAdditions.h"

NS_ASSUME_NONNULL_BEGIN

@interface DatabaseManagement : NSObject

/** App 启动时，为数据库做一些准备工作
 */
+ (void)prepareWhenApplicationLaunch;

/** 创建一张表
*/
+ (void)creatTableWithName:(NSString *)tableName sql:(NSString *)sql;

/** 销毁一张表
 */
+ (void)dropTableWithName:(NSString *)tableName;

/** 清空一张表
 */
+ (void)emptyTableWithName:(NSString *)tableName;

/** 使用事务执行一些操作
 * 在分线程中执行
 */
+ (void)databaseChildThreadInTransaction:(void (^)(FMDatabase *database, BOOL *rollback))block;

/** 使用事务执行一些操作
 * 在当前线程中执行（一般用于创建表时使用）
 */
+ (void)databaseCurrentThreadInTransaction:(void (^)(FMDatabase *database, BOOL *rollback))block;

/** 清空数据
 */
+ (void)clearSqlite;

/** 移除数据库中的每张表
*/
+ (void)dropSqlite;

+ (void)info;

@end

NS_ASSUME_NONNULL_END

/*
 

 
####2、SQLite 函数

[SQLite 函数](https://www.sqlite.org/cintro.html) 提供了对数据库的操作！







 
 序号
 API & 描述
 
 
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
 
 
 
 SQLite sqlite_version 函数
 SQLite sqlite_version 函数返回 SQLite 库的版本。




 
 */
