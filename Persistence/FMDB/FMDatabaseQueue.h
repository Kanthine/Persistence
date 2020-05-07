//
//  FMDatabaseQueue.h
//  fmdb
//
//  Created by August Mueller on 6/22/11.
//  Copyright 2011 Flying Meat Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FMDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/** 使用 FMDatabase 在多线程下并发访问数据库，会引起数据竞争！此时使用 FMDatabaseQueue 避免这些问题！
 * FMDatabaseQueue 在 FMDatabase 的基础功能上，增加了一个GCD串行队列的功能！
 * 针对数据库的所有操作，在当前上下文所处的线程中，队列中的任务按顺序执行，查询和更新就不会互相干扰！
 *
 * FMDatabaseQueue 在创建数据库的时候，默认打开数据库！
 *
 * 可以根据数据库路径创建一个单例： FMDatabaseQueue *queue = [FMDatabaseQueue databaseQueueWithPath:aPath];
 * 然后像这样使用它:
    [queue inDatabase:^(FMDatabase *db) {
        [db executeUpdate:@"INSERT INTO myTable VALUES (?)", @(1)];

        FMResultSet *rs = [db executeQuery:@"select * from foo"];
        while ([rs next]) {
            //…
        }
    }];
 *
 * 也可以在事务中完成:
    [queue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        [db executeUpdate:@"INSERT INTO myTable VALUES (?)", @(1)];
        
        if (whoopsSomethingWrongHappened) {
            *rollback = YES;
            return;
        }
        // etc…
        [db executeUpdate:@"INSERT INTO myTable VALUES (?)", [NSNumber numberWithInt:4]];
    }];
 *
 * @note 由于 FMDatabaseQueue 本质是一个串行队列，所以不能嵌套使用！
 */
@interface FMDatabaseQueue : NSObject

/** 数据库路径
 */
@property (atomic, retain, nullable) NSString *path;

/** 开启标志
 */
@property (atomic, readonly) int openFlags;

/** 自定义虚拟文件名称
 */
@property (atomic, copy, nullable) NSString *vfsName;

///----------------------------------------------------
/// @name 队列的初始化、打开、关闭
///----------------------------------------------------

/** 根据指定的数据库路径路径实例化一个队列
 *
 * 标志 openFlags 的取值：
 *      SQLITE_OPEN_READONLY : 数据库只读，如果数据库不存在，则返回一个错误；
 *      SQLITE_OPEN_READWRITE 打开数据库进行读写操作，或者文件被读保护的情况下仅进行写操作。此时数据库必须存在，否则将返回一个错误。
 *      SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE 类似于 -open 方法： 打开数据库进行读写操作，如果数据库不存在就创建它。
 *
 *  vfsName 自定义虚拟文件的名称
 *
 * @note 在创建数据库的时候，默认打开数据库！
 */
+ (nullable instancetype)databaseQueueWithPath:(NSString * _Nullable)aPath;
+ (nullable instancetype)databaseQueueWithURL:(NSURL * _Nullable)url;
+ (nullable instancetype)databaseQueueWithPath:(NSString * _Nullable)aPath flags:(int)openFlags;
+ (nullable instancetype)databaseQueueWithURL:(NSURL * _Nullable)url flags:(int)openFlags;
- (nullable instancetype)initWithPath:(NSString * _Nullable)aPath;
- (nullable instancetype)initWithURL:(NSURL * _Nullable)url;
- (nullable instancetype)initWithPath:(NSString * _Nullable)aPath flags:(int)openFlags;
- (nullable instancetype)initWithURL:(NSURL * _Nullable)url flags:(int)openFlags;
- (nullable instancetype)initWithPath:(NSString * _Nullable)aPath flags:(int)openFlags vfs:(NSString * _Nullable)vfsName;
- (nullable instancetype)initWithURL:(NSURL * _Nullable)url flags:(int)openFlags vfs:(NSString * _Nullable)vfsName;

/** 获取 FMDatabase 类，用于实例化数据库对象。
 */
+ (Class)databaseClass;

/** 关闭队列使用的数据库
 */
- (void)close;

/** 中断数据库操作
 */
- (void)interrupt;

///-----------------------------------------------
/// @name 将数据库操作分派到队列
///-----------------------------------------------

/** 在队列上同步执行数据库操作
 * @param block 要在 FMDatabaseQueue 队列上运行的代码
 */
- (void)inDatabase:(__attribute__((noescape)) void (^)(FMDatabase *db))block;

/** 使用事务在 串行dispatch_queue 同步执行数据库操作
 * @note 没有开辟分线程，在当前线程中操作！
 * @note 不可以嵌套使用，否则造成线程死锁；
 * @warning 与 SQLite 的 BEGIN TRANSACTION 不同，此方法当前执行的是互斥事务，而不是延迟事务；
 *       在FMDB的未来版本中，这种行为可能会改变，因此该方法最终可能采用标准SQLite行为并执行延迟事务。
 *       建议使用 -beginExclusiveTransaction ，保证代码在未来不会被修改。
 */
- (void)inTransaction:(__attribute__((noescape)) void (^)(FMDatabase *db, BOOL *rollback))block;

/** 使用延迟事务在队列上同步执行数据库操作
 */
- (void)inDeferredTransaction:(__attribute__((noescape)) void (^)(FMDatabase *db, BOOL *rollback))block;

/** 使用互斥事务在队列上同步执行数据库操作。
 */
- (void)inExclusiveTransaction:(__attribute__((noescape)) void (^)(FMDatabase *db, BOOL *rollback))block;

/** 使用事务立即在队列上同步执行数据库操作。
 */
- (void)inImmediateTransaction:(__attribute__((noescape)) void (^)(FMDatabase *db, BOOL *rollback))block;

///-----------------------------------------------
/// @name 将数据库操作分派到队列
///-----------------------------------------------

/** 使用 保存点机制 同步执行数据库操作
 *
 * @note  不能嵌套操作，因为调用它会从池中拉出另一个数据库，会得到一个死锁。
 *        如果需要嵌套，用 FMDatabase 的 -startSavePointWithName:error: 代替。
 */
- (NSError * _Nullable)inSavePoint:(__attribute__((noescape)) void (^)(FMDatabase *db, BOOL *rollback))block;

///-----------------
/// @name Checkpoint
///-----------------

/** 手动配置 WAL 检查点
 * @param name sqlite3_wal_checkpoint_v2() 的数据库名称
 * @param checkpointMode  sqlite3_wal_checkpoint_v2() 的检查点类型
 * @param logFrameCount 如果不为NULL，则将其设置为日志文件中的总帧数，如果检查点由于错误或数据库没有处于WAL模式而无法运行，则将其设置为-1。
 * @param checkpointCount 如果不是NULL,那么这将检查点帧总数日志文件(包括检查点之前任何已经调用的函数)，如果检查点由于错误或数据库不在WAL模式下而无法运行，则为-1。
 * @return 成功返回 YES；
 */
- (BOOL)checkpoint:(FMDBCheckpointMode)checkpointMode name:(NSString * _Nullable)name logFrameCount:(int * _Nullable)logFrameCount checkpointCount:(int * _Nullable)checkpointCount error:(NSError * _Nullable *)error;
- (BOOL)checkpoint:(FMDBCheckpointMode)checkpointMode name:(NSString * _Nullable)name error:(NSError * _Nullable *)error;
- (BOOL)checkpoint:(FMDBCheckpointMode)checkpointMode error:(NSError * _Nullable *)error;

@end

NS_ASSUME_NONNULL_END
