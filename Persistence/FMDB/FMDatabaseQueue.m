//
//  FMDatabaseQueue.m
//  fmdb
//
//  Created by August Mueller on 6/22/11.
//  Copyright 2011 Flying Meat Inc. All rights reserved.
//

#import "FMDatabaseQueue.h"
#import "FMDatabase.h"

#if FMDB_SQLITE_STANDALONE
#import <sqlite3/sqlite3.h>
#else
#import <sqlite3.h>
#endif

//开启的事务类型
typedef NS_ENUM(NSInteger, FMDBTransaction) {
    FMDBTransactionExclusive,//开始互斥事务
    FMDBTransactionDeferred,//开始一个延迟的事务
    FMDBTransactionImmediate,//立即开启事务
};

/** 死锁检测，通过查看 -inDatabase: 是否套用并导致死锁。
 */
static const void * const kDispatchQueueSpecificKey = &kDispatchQueueSpecificKey;

@interface FMDatabaseQueue () {
    dispatch_queue_t    _queue;//串行队列
    FMDatabase          *_db;//数据库操作
}
@end

@implementation FMDatabaseQueue

+ (instancetype)databaseQueueWithPath:(NSString *)aPath {
    FMDatabaseQueue *q = [[self alloc] initWithPath:aPath];
    FMDBAutorelease(q);
    return q;
}

+ (instancetype)databaseQueueWithURL:(NSURL *)url {
    return [self databaseQueueWithPath:url.path];
}

+ (instancetype)databaseQueueWithPath:(NSString *)aPath flags:(int)openFlags {
    FMDatabaseQueue *q = [[self alloc] initWithPath:aPath flags:openFlags];
    FMDBAutorelease(q);
    return q;
}

+ (instancetype)databaseQueueWithURL:(NSURL *)url flags:(int)openFlags {
    return [self databaseQueueWithPath:url.path flags:openFlags];
}

+ (Class)databaseClass {
    return [FMDatabase class];
}

- (instancetype)initWithURL:(NSURL *)url flags:(int)openFlags vfs:(NSString *)vfsName {
    return [self initWithPath:url.path flags:openFlags vfs:vfsName];
}

- (instancetype)initWithPath:(NSString*)aPath flags:(int)openFlags vfs:(NSString *)vfsName {
    self = [super init];
    if (self != nil) {
        _db = [[[self class] databaseClass] databaseWithPath:aPath];
        FMDBRetain(_db);
        
#if SQLITE_VERSION_NUMBER >= 3005000
        //在创建数据库的时候，默认打开数据库！
        BOOL success = [_db openWithFlags:openFlags vfs:vfsName];
#else
        BOOL success = [_db open];
#endif
        if (!success) {
            NSLog(@"Could not create database queue for path %@", aPath);
            FMDBRelease(self);
            return 0x00;
        }
        
        _path = FMDBReturnRetained(aPath);
        _queue = dispatch_queue_create([[NSString stringWithFormat:@"fmdb.%@", self] UTF8String], NULL);
        //为 _queue 设置标识数据：指定的键，值为 self 的地址
        dispatch_queue_set_specific(_queue, kDispatchQueueSpecificKey, (__bridge void *)self, NULL);
        _openFlags = openFlags;
        _vfsName = [vfsName copy];
    }
    return self;
}

- (instancetype)initWithPath:(NSString *)aPath flags:(int)openFlags {
    return [self initWithPath:aPath flags:openFlags vfs:nil];
}

- (instancetype)initWithURL:(NSURL *)url flags:(int)openFlags {
    return [self initWithPath:url.path flags:openFlags vfs:nil];
}

- (instancetype)initWithURL:(NSURL *)url {
    return [self initWithPath:url.path];
}

- (instancetype)initWithPath:(NSString *)aPath {
    // default flags for sqlite3_open
    return [self initWithPath:aPath flags:SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE vfs:nil];
}

- (instancetype)init {
    return [self initWithPath:nil];
}

- (void)dealloc {
    FMDBRelease(_db);
    FMDBRelease(_path);
    FMDBRelease(_vfsName);
    
    if (_queue) {
        FMDBDispatchQueueRelease(_queue);
        _queue = 0x00;
    }
#if ! __has_feature(objc_arc)
    [super dealloc];
#endif
}

- (void)close {
    FMDBRetain(self);
    dispatch_sync(_queue, ^() {
        [self->_db close];
        FMDBRelease(_db);
        self->_db = 0x00;
    });
    FMDBRelease(self);
}

- (void)interrupt {
    [[self database] interrupt];
}

//数据库处于打开状态
- (FMDatabase*)database {
    if (![_db isOpen]) {
        if (!_db) {
           _db = FMDBReturnRetained([[[self class] databaseClass] databaseWithPath:_path]);
        }
        
#if SQLITE_VERSION_NUMBER >= 3005000
        BOOL success = [_db openWithFlags:_openFlags vfs:_vfsName];
#else
        BOOL success = [_db open];
#endif
        if (!success) {
            NSLog(@"FMDatabaseQueue could not reopen database for path %@", _path);
            FMDBRelease(_db);
            _db  = 0x00;
            return 0x00;
        }
    }
    return _db;
}

- (void)inDatabase:(__attribute__((noescape)) void (^)(FMDatabase *db))block {
#ifndef NDEBUG
    //断言：确保 inDatabase: 不会套用造成死锁
    FMDatabaseQueue *currentSyncQueue = (__bridge id)dispatch_get_specific(kDispatchQueueSpecificKey);
    assert(currentSyncQueue != self && "inDatabase: was called reentrantly on the same queue, which would lead to a deadlock");
#endif
    
    FMDBRetain(self);
    dispatch_sync(_queue, ^() {//同步执行串行队列
        
        FMDatabase *db = [self database];
        block(db);
        if ([db hasOpenResultSets]) {
            NSLog(@"Warning: there is at least one open result set around after performing [FMDatabaseQueue inDatabase:]");
            
#if defined(DEBUG) && DEBUG
            NSSet *openSetCopy = FMDBReturnAutoreleased([[db valueForKey:@"_openResultSets"] copy]);
            for (NSValue *rsInWrappedInATastyValueMeal in openSetCopy) {
                FMResultSet *rs = (FMResultSet *)[rsInWrappedInATastyValueMeal pointerValue];
                NSLog(@"query: '%@'", [rs query]);
            }
#endif
        }
    });
    FMDBRelease(self);
}

- (void)beginTransaction:(FMDBTransaction)transaction withBlock:(void (^)(FMDatabase *db, BOOL *rollback))block {
    FMDBRetain(self);
    dispatch_sync(_queue, ^() { //同步执行串行队列
        BOOL shouldRollback = NO;
        switch (transaction) {
            case FMDBTransactionExclusive:
                [[self database] beginTransaction];//默认开始互斥事务
                break;
            case FMDBTransactionDeferred:
                [[self database] beginDeferredTransaction];//开始一个延迟事务
                break;
            case FMDBTransactionImmediate:
                [[self database] beginImmediateTransaction];//立即开启事务
                break;
        }
        block([self database], &shouldRollback);
        if (shouldRollback) {
            [[self database] rollback];
        }else {
            [[self database] commit];
        }
    });
    FMDBRelease(self);
}

- (void)inTransaction:(__attribute__((noescape)) void (^)(FMDatabase *db, BOOL *rollback))block {
    [self beginTransaction:FMDBTransactionExclusive withBlock:block];
}

- (void)inDeferredTransaction:(__attribute__((noescape)) void (^)(FMDatabase *db, BOOL *rollback))block {
    [self beginTransaction:FMDBTransactionDeferred withBlock:block];
}

- (void)inExclusiveTransaction:(__attribute__((noescape)) void (^)(FMDatabase *db, BOOL *rollback))block {
    [self beginTransaction:FMDBTransactionExclusive withBlock:block];
}

- (void)inImmediateTransaction:(__attribute__((noescape)) void (^)(FMDatabase * _Nonnull, BOOL * _Nonnull))block {
    [self beginTransaction:FMDBTransactionImmediate withBlock:block];
}

- (NSError*)inSavePoint:(__attribute__((noescape)) void (^)(FMDatabase *db, BOOL *rollback))block {
#if SQLITE_VERSION_NUMBER >= 3007000
    static unsigned long savePointIdx = 0;
    __block NSError *err = 0x00;
    FMDBRetain(self);
    dispatch_sync(_queue, ^() { 
        NSString *name = [NSString stringWithFormat:@"savePoint%ld", savePointIdx++];
        BOOL shouldRollback = NO;
        if ([[self database] startSavePointWithName:name error:&err]) {// 设置保存点
            block([self database], &shouldRollback);
            if (shouldRollback) {//如果需要回滚
                //回滚到保存点
                [[self database] rollbackToSavePointWithName:name error:&err];
            }
            //刪除保存点
            [[self database] releaseSavePointWithName:name error:&err];
        }
    });
    FMDBRelease(self);
    return err;
#else
    NSString *errorMessage = NSLocalizedStringFromTable(@"Save point functions require SQLite 3.7", @"FMDB", nil);
    if (_db.logsErrors) NSLog(@"%@", errorMessage);
    return [NSError errorWithDomain:@"FMDatabase" code:0 userInfo:@{NSLocalizedDescriptionKey : errorMessage}];
#endif
}

- (BOOL)checkpoint:(FMDBCheckpointMode)mode error:(NSError * __autoreleasing *)error{
    return [self checkpoint:mode name:nil logFrameCount:NULL checkpointCount:NULL error:error];
}

- (BOOL)checkpoint:(FMDBCheckpointMode)mode name:(NSString *)name error:(NSError * __autoreleasing *)error{
    return [self checkpoint:mode name:name logFrameCount:NULL checkpointCount:NULL error:error];
}

- (BOOL)checkpoint:(FMDBCheckpointMode)mode name:(NSString *)name logFrameCount:(int * _Nullable)logFrameCount checkpointCount:(int * _Nullable)checkpointCount error:(NSError * __autoreleasing _Nullable * _Nullable)error{
    __block BOOL result;
    __block NSError *blockError;
    
    FMDBRetain(self);
    dispatch_sync(_queue, ^() {
        result = [self.database checkpoint:mode name:name logFrameCount:logFrameCount checkpointCount:checkpointCount error:&blockError];
    });
    FMDBRelease(self);
    
    if (error) {
        *error = blockError;
    }
    return result;
}

@end
