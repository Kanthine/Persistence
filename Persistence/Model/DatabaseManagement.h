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

+ (void)clearSqlite;

+ (void)info;

@end

NS_ASSUME_NONNULL_END

/** Sql 语句
 *
 * 建表：
 *      @"CREATE TABLE Persons (id INTEGER PRIMARY KEY,name TEXT UNIQUE NOT NULL,age INTEGER)"
 *      主键：PRIMARY KEY，数据类型为 INTEGER
 *      非空：NOT NULL
 *      唯一性：UNIQUE
 *
 * 插入：若有唯一键，则只能插入一次！再次插入，插入失败！
 *      @"INSERT INTO Persons (name,age) VALUES (? , ?)",@"张三",@(69)
 *
 * 替代：若没有唯一键，则插入！若有唯一键，则覆盖具有唯一键的数据！
 *      @"REPLACE INTO Persons (name,age) VALUES (? , ?)",@"张三",@(69)
 *
 * 更新：修改表中满足条件的数据
 *      如果表中有多条 age = 12，则全部修改
 *      被修改的数据如果具有唯一性，则只能修改其中一条数据！
 *     @"UPDATE Persons SET name = ? WHERE age = ?",@"李四",@(12)
 *
 * 删除：删除表中满足条件的数据
 *      如果表中有多条 age  < 20，则全部删除
 *    @"DELETE FROM Persons WHERE age < ?",@(20)
 *
 * 移除表：移除数据库中的某张表
 *      @"DROP TABLE IF EXISTS PhoneCodeModel"
 */
