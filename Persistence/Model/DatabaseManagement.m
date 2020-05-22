//
//  DatabaseManagement.m
//  Persistence
//
//  Created by 苏沫离 on 2018/4/24.
//  Copyright © 2018 苏沫离. All rights reserved.
//

#import "DatabaseManagement.h"
#import "PhoneCodeModel+DAO.h"
#import "ProvincesModel+DAO.h"
#import "FMDatabaseQueue.h"

NSString *groupSqliteFile(void){
    return [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/fmdb_Data.sqlite"];
}

@implementation DatabaseManagement

+ (void)prepareWhenApplicationLaunch{
    NSLog(@"sqlite === %@",groupSqliteFile());
    //创建表
    NSInvocationOperation *tableOperation = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(creatGroupTable) object:nil];
    tableOperation.queuePriority = NSOperationQueuePriorityVeryHigh;
    
    //移除无效文件
    NSInvocationOperation *removeOperation = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(removeUselessFile) object:nil];
    removeOperation.queuePriority = NSOperationQueuePriorityLow;
    
    [[self shareThreadQueue] addOperation:tableOperation];
    [[self shareThreadQueue] addOperation:removeOperation];
}

+ (FMDatabaseQueue *)databaseQueue{
    static FMDatabaseQueue *databaseQueue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (databaseQueue == nil){
            databaseQueue = [[FMDatabaseQueue alloc] initWithPath:groupSqliteFile()];
        }
    });
    return databaseQueue;
}

/** 实例化一个全局任务队列，限定Operation并发量
 */
+ (NSOperationQueue *)shareThreadQueue{
    static NSOperationQueue *threadQueue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if (threadQueue == nil){
            threadQueue = [[NSOperationQueue alloc] init];
            threadQueue.maxConcurrentOperationCount = 6;
            threadQueue.name = @"本地数据队列";
        }
    });
    return threadQueue;
}

/** 创建一张表
*/
+ (void)creatTableWithName:(NSString *)tableName sql:(NSString *)sql{
    [DatabaseManagement databaseCurrentThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        if (![database tableExists:tableName]){
            [database executeUpdate:sql];
        }
    }];
}

/** 销毁一张表
 */
+ (void)dropTableWithName:(NSString *)tableName{
    NSString *sql = [NSString stringWithFormat:@"DROP TABLE IF EXISTS %@",tableName];
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [database executeUpdate:sql];
    }];
}

+ (void)emptyTableWithName:(NSString *)tableName{
    NSString *dropSql = [NSString stringWithFormat:@"DROP TABLE IF EXISTS %@",tableName];
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        
        NSString *creatSql;
        
        FMResultSet *resultSet = database.getSchema;
        while ([resultSet next]){
            NSString *name = [resultSet stringForColumn:@"name"];
            if ([name isEqualToString:tableName]) {
                creatSql = [resultSet stringForColumn:@"sql"];
                break;
            }
        }
        [resultSet close];
        
        [database executeUpdate:dropSql];
        if (creatSql) {
            [database executeUpdate:creatSql];
        }
    }];
}

+ (void)databaseChildThreadInTransaction:(void (^)(FMDatabase *database, BOOL *rollback))block{
    [[self shareThreadQueue] addOperationWithBlock:^{
        [DatabaseManagement.databaseQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
            [db setShouldCacheStatements:YES];
            block(db,rollback);
        }];
    }];
}

+ (void)databaseCurrentThreadInTransaction:(void (^)(FMDatabase *database, BOOL *rollback))block{
    [DatabaseManagement.databaseQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        block(db,rollback);
    }];
}

+ (void)creatGroupTable{
    [ProvincesModel creatTable];
    [PhoneCodeModel creatTable];
}




/** 移除缓数据
 */
+ (void)clearSqlite{
    //如果还有针对数据库的操作，则全部取消
    if ([self shareThreadQueue].operationCount > 0){
        [[self shareThreadQueue] cancelAllOperations];
    }
    
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [database interrupt];//中断数据库操作
        
        [database executeUpdate:@"UPDATE sqlite_sequence SET seq = 0"];
        
        FMResultSet *resultSet = database.getSchema;
        while ([resultSet next]){
            NSString *tbl_name = [resultSet stringForColumn:@"tbl_name"];
            if (tbl_name) {
                NSString *deleteSql = [NSString stringWithFormat:@"DELETE FROM %@",tbl_name];
                [database executeUpdate:deleteSql];
            }
        }
        [resultSet close];

    }];
}

+ (void)dropSqlite{
    if ([self shareThreadQueue].operationCount > 0){
        [[self shareThreadQueue] cancelAllOperations];
    }
    
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [database interrupt];//中断数据库操作
        
        FMResultSet *resultSet = database.getSchema;
        while ([resultSet next]){
            
            NSString *tbl_name = [resultSet stringForColumn:@"tbl_name"];
            if (tbl_name) {
                NSString *dropSql = [NSString stringWithFormat:@"DROP TABLE IF EXISTS %@",tbl_name];
                [database executeUpdate:dropSql];
            }
        }
        [resultSet close];
    }];

}

+ (void)removeUselessFile{
    
}

+ (void)info{
    NSLog(@"vfsName ---- %@",DatabaseManagement.databaseQueue.vfsName);

    [DatabaseManagement.databaseQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
//        dateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        dateFormatter.timeZone = [NSTimeZone systemTimeZone];//系统所在时区
        dateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"zh-CN"];
        [db setDateFormat:dateFormatter];
        
        NSLog(@"hasDateFormatter -- %d",db.hasDateFormatter);

        NSLog(@"lastInsertRowId -- %lld",db.lastInsertRowId);
        NSLog(@"changes -- %d",db.changes);

        NSLog(@"goodConnection -- %d",db.goodConnection);

//        NSLog(@"cachedStatements ---- %@",db.cachedStatements);
        
        NSLog(@"userVersion ---- %u",db.userVersion);
        NSLog(@"applicationID -- %d",db.applicationID);
        
//        FMResultSet *resultSet = [db getTableSchema:@"Persons"];
//        while ([resultSet next]){
//            NSLog(@"Persons Schema ： %@",resultSet.resultDictionary);
//        }
//        [resultSet close];
    }];
}

@end
