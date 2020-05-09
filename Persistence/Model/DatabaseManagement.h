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
