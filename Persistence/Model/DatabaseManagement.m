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

/** 退出登录，移除缓存数据
 */
+ (void)clearSqlite{
    //如果还有针对数据库的操作，则全部取消
    if ([self shareThreadQueue].operationCount > 0){
        [[self shareThreadQueue] cancelAllOperations];
    }
    
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [database interrupt];//中断数据库操作
        
        NSMutableDictionary *muDict = [NSMutableDictionary dictionary];
        
        FMResultSet *resultSet = database.getSchema;
        while ([resultSet next]){
            NSString *tbl_name = [resultSet stringForColumn:@"tbl_name"];
            NSString *sql = [resultSet stringForColumn:@"sql"];
            if (tbl_name && sql) {
                [muDict setObject:sql forKey:tbl_name];
            }
        }
        [resultSet close];
        
        [muDict enumerateKeysAndObjectsUsingBlock:^(NSString*  _Nonnull tbl_name, NSString*  _Nonnull sql, BOOL * _Nonnull stop) {
            NSString *dropSql = [NSString stringWithFormat:@"DROP TABLE IF EXISTS %@",tbl_name];
            [database executeUpdate:dropSql];
            [database executeUpdate:sql];
        }];
    }];
}

+ (void)removeUselessFile{
    
}

+ (void)info{
    NSLog(@"vfsName ---- %@",DatabaseManagement.databaseQueue.vfsName);

    [DatabaseManagement.databaseQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        
        
        NSLog(@"lastInsertRowId -- %d",db.lastInsertRowId);
        NSLog(@"changes -- %d",db.changes);

        NSLog(@"goodConnection -- %d",db.goodConnection);

        NSLog(@"cachedStatements ---- %@",db.cachedStatements);
        
        NSLog(@"userVersion ---- %u",db.userVersion);
        NSLog(@"applicationID -- %d",db.applicationID);
        
//        resultSet = [db getTableSchema:@"PhoneCodeModel"];
//        while ([resultSet next]){
//            NSLog(@"getSchema ====== %@",resultSet.resultDictionary);
//        }
//        [resultSet close];
    }];
}

@end
