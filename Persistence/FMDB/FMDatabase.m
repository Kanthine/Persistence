#import "FMDatabase.h"
#import <unistd.h>
#import <objc/runtime.h>

#if FMDB_SQLITE_STANDALONE
#import <sqlite3/sqlite3.h>
#else
#import <sqlite3.h>
#endif

@interface FMDatabase ()

{
    void*               _db;//打开的SQLite数据库
    BOOL                _isExecutingStatement;
    NSTimeInterval      _startBusyRetryTime;
    
    NSMutableSet        *_openResultSets;
    NSMutableSet        *_openFunctions;
    
    NSDateFormatter     *_dateFormat;
}

NS_ASSUME_NONNULL_BEGIN

- (FMResultSet * _Nullable)executeQuery:(NSString *)sql withArgumentsInArray:(NSArray * _Nullable)arrayArgs orDictionary:(NSDictionary * _Nullable)dictionaryArgs orVAList:(va_list)args;
- (BOOL)executeUpdate:(NSString *)sql error:(NSError * _Nullable __autoreleasing *)outErr withArgumentsInArray:(NSArray * _Nullable)arrayArgs orDictionary:(NSDictionary * _Nullable)dictionaryArgs orVAList:(va_list)args;

NS_ASSUME_NONNULL_END

@end

@implementation FMDatabase

@synthesize shouldCacheStatements = _shouldCacheStatements;
@synthesize maxBusyRetryTimeInterval = _maxBusyRetryTimeInterval;

#pragma mark FMDatabase 实例化、释放

// FMDBReturnAutoReleased() 是为了兼容MRC和ARC
//FMDatabase 实例化 本质上只是给了数据库一个名字，并没有真实创建或者获取数据库。
// -open 方法才是真正获取到数据库，其本质调用SQLite的 sqlite3_open() 函数
+ (instancetype)databaseWithPath:(NSString *)aPath {
    return FMDBReturnAutoreleased([[self alloc] initWithPath:aPath]);
}

+ (instancetype)databaseWithURL:(NSURL *)url {
    return FMDBReturnAutoreleased([[self alloc] initWithURL:url]);
}

- (instancetype)init {
    return [self initWithPath:nil];
}

- (instancetype)initWithURL:(NSURL *)url {
    return [self initWithPath:url.path];
}

- (instancetype)initWithPath:(NSString *)path {
    assert(sqlite3_threadsafe()); // whoa there big boy- gotta make sure sqlite it happy with what we're going to do.
    self = [super init];
    if (self) {
        _databasePath               = [path copy];
        _openResultSets             = [[NSMutableSet alloc] init];
        _db                         = nil;//数据库为空
        _logsErrors                 = YES;
        _crashOnErrors              = NO;
        _maxBusyRetryTimeInterval   = 2;
        _isOpen                     = NO;//默认数据库关闭
    }
    return self;
}

#if ! __has_feature(objc_arc)
- (void)finalize {
    [self close];
    [super finalize];
}
#endif

- (void)dealloc {
    [self close];
    FMDBRelease(_openResultSets);
    FMDBRelease(_cachedStatements);
    FMDBRelease(_dateFormat);
    FMDBRelease(_databasePath);
    FMDBRelease(_openFunctions);
    
#if ! __has_feature(objc_arc)
    [super dealloc];
#endif
}

- (NSURL *)databaseURL {
    return _databasePath ? [NSURL fileURLWithPath:_databasePath] : nil;
}

+ (NSString*)FMDBUserVersion {
    return @"2.7.6";
}

// returns 0x0240 for version 2.4.  This makes it super easy to do things like:
// /* need to make sure to do X with FMDB version 2.4 or later */
// if ([FMDatabase FMDBVersion] >= 0x0240) { … }

+ (SInt32)FMDBVersion {
    
    // we go through these hoops so that we only have to change the version number in a single spot.
    static dispatch_once_t once;
    static SInt32 FMDBVersionVal = 0;
    
    dispatch_once(&once, ^{
        NSString *prodVersion = [self FMDBUserVersion];
        if ([[prodVersion componentsSeparatedByString:@"."] count] < 3) {
            prodVersion = [prodVersion stringByAppendingString:@".0"];
        }
        NSString *junk = [prodVersion stringByReplacingOccurrencesOfString:@"." withString:@""];
        char *e = nil;
        FMDBVersionVal = (int) strtoul([junk UTF8String], &e, 16);
    });
    
    return FMDBVersionVal;
}

/**************  SQLite information  **************/

+ (NSString*)sqliteLibVersion {
    return [NSString stringWithFormat:@"%s", sqlite3_libversion()];
}

+ (BOOL)isSQLiteThreadSafe {
    // make sure to read the sqlite headers on this guy!
    return sqlite3_threadsafe() != 0;
}

- (void*)sqliteHandle {
    return _db;
}

/** 如果 filename 参数是 NULL 或 ':memory:'，那么 sqlite3_open() 将会在 RAM 中创建一个内存数据库，这只会在 session 的有效时间内持续。
 */
- (const char*)sqlitePath {
    if (!_databasePath) {
        return ":memory:";// sqlite3_open() 将会在 RAM 中创建一个内存数据库,这只会在 session 的有效时间内持续。
    }
    if ([_databasePath length] == 0) {
        return ""; //这会在 tmp 创建一个数据库
    }
    return [_databasePath fileSystemRepresentation];
}

#pragma mark 打开、关闭 数据库

/** 根据指定路径打开一个 SQLite 数据库，返回一个用于其他 SQLite 程序的数据库连接对象
 * @param filename UTF-8编码的数据库名称
 * @param ppDb SQLite数据库连接对象
int sqlite3_open(const char *filename,sqlite3 **ppDb);
 */

/** 打开数据库打开 : 对 SQLite 中 sqlite3_open() 函数的封装使用
 * 数据库打开后根据 _maxBusyRetryTimeInterval 将数据库线程停顿一段时间，然后继续向下执行
 */
- (BOOL)open {
    if (_isOpen) {
        return YES;
    }
    if (_db) {// 如果之前尝试打开但失败，请确保在再次尝试之前关闭它
        [self close];
    }
    
    //调用sqlite3_open()函数创建数据库
    int err = sqlite3_open([self sqlitePath], (sqlite3**)&_db);
    if(err != SQLITE_OK) {
        NSLog(@"error opening!: %d", err);
        return NO;
    }
    
    //当执行这段代码的时候，数据库正在被其他线程访问，就需要给他设置重试时间，
    if (_maxBusyRetryTimeInterval > 0.0) {
        [self setMaxBusyRetryTimeInterval:_maxBusyRetryTimeInterval];
    }
    _isOpen = YES;
    return YES;
}



- (BOOL)openWithFlags:(int)flags {
    return [self openWithFlags:flags vfs:nil];
}

- (BOOL)openWithFlags:(int)flags vfs:(NSString *)vfsName {
#if SQLITE_VERSION_NUMBER >= 3005000
    if (_isOpen) {
        return YES;
    }
    if (_db) {// 如果之前尝试打开但失败，请确保在再次尝试之前关闭它
        [self close];
    }
    
    // now open database
    
    int err = sqlite3_open_v2([self sqlitePath], (sqlite3**)&_db, flags, [vfsName UTF8String]);
    if(err != SQLITE_OK) {
        NSLog(@"error opening!: %d", err);
        return NO;
    }
    if (_maxBusyRetryTimeInterval > 0.0) {
        [self setMaxBusyRetryTimeInterval:_maxBusyRetryTimeInterval];
    }
    _isOpen = YES;
    return YES;
#else
    NSLog(@"openWithFlags requires SQLite 3.5");
    return NO;
#endif
}

/** 关闭数据库连接 */
- (BOOL)close {
    [self clearCachedStatements];//清理缓存
    [self closeOpenResultSets];//清理结果集
    if (!_db) {//如果数据库不存在
        return YES;
    }
    
    int  rc;
    BOOL retry;
    BOOL triedFinalizingOpenStatements = NO;
    do {
        retry   = NO;
        rc      = sqlite3_close(_db);
        if (SQLITE_BUSY == rc || SQLITE_LOCKED == rc) {
            if (!triedFinalizingOpenStatements) {
                triedFinalizingOpenStatements = YES;
                sqlite3_stmt *pStmt;
                while ((pStmt = sqlite3_next_stmt(_db, nil)) !=0) {
                    NSLog(@"Closing leaked statement");
                    sqlite3_finalize(pStmt);
                    retry = YES;
                }
            }
        }else if (SQLITE_OK != rc) {
            NSLog(@"error closing!: %d", rc);
        }
    }
    while (retry);
    _db = nil;//数据库指针指向 nil
    _isOpen = false;//状态改为 NO
    return YES;
}

#pragma mark Busy handler routines

// NOTE: appledoc seems to choke on this function for some reason;
//       so when generating documentation, you might want to ignore the
//       .m files so that it only documents the public interfaces outlined
//       in the .h files.
//
//       This is a known appledoc bug that it has problems with C functions
//       within a class implementation, but for some reason, only this
//       C function causes problems; the rest don't. Anyway, ignoring the .m
//       files with appledoc will prevent this problem from occurring.

// 该函数就是简单调用 sqlite3_sleep() 来挂起线程
static int FMDBDatabaseBusyHandler(void *f, int count) {
    FMDatabase *self = (__bridge FMDatabase*)f;
    
    if (count == 0) {// count为0，表示第一次执行回调函数
        self->_startBusyRetryTime = [NSDate timeIntervalSinceReferenceDate];
        return 1;
    }
    
    // 使用delta变量控制执行回调函数的次数，每次挂起50~100ms
    // 所以maxBusyRetryTimeInterval的作用就在这体现出来了
    // 当挂起的时长大于maxBusyRetryTimeInterval，就返回0，并停止执行该回调函数了
    NSTimeInterval delta = [NSDate timeIntervalSinceReferenceDate] - (self->_startBusyRetryTime);
    
    if (delta < [self maxBusyRetryTimeInterval]) {
        
        // 使用sqlite3_sleep每次当前线程挂起50~100ms
        int requestedSleepInMillseconds = (int) arc4random_uniform(50) + 50;
        int actualSleepInMilliseconds = sqlite3_sleep(requestedSleepInMillseconds);
        
        // 如果实际挂起的时长与想要挂起的时长不一致，可能是因为构建SQLite时没将HAVE_USLEEP置为1
        if (actualSleepInMilliseconds != requestedSleepInMillseconds) {
            NSLog(@"WARNING: Requested sleep of %i milliseconds, but SQLite returned %i. Maybe SQLite wasn't built with HAVE_USLEEP=1?", requestedSleepInMillseconds, actualSleepInMilliseconds);
        }
        return 1;
    }
    
    return 0;
}

/** 程序运行过程中，如果有其他进程或者线程在读写数据库，那么sqlite3_busy_handler() 会不断调用回调函数，直到其他进程或者线程释放锁。
 * 获得锁之后，不会再调用回调函数，从而向下执行，进行数据库操作。
 * 该函数是在获取不到锁的时候，以执行回调函数的次数来进行延迟，等待其他进程或者线程操作数据库结束，从而获得锁操作数据库。
 
 
 第一个参数: 告知哪个数据库需要设置busy handler。
 第二个参数: 回调函数，当你调用该回调函数时，需传递给它的一个void*的参数的拷贝，也即sqlite3_busy_handler()的第三个参数；
           另一个需要传给回调函数的int参数是表示这次锁事件，该回调函数被调用的次数。如果回调函数返回０时，将不再尝试再次访问数据库而返回SQLITE_BUSY或者SQLITE_IOERR_BLOCKED。如果回调函数返回非０,　将会不断尝试操作数据库。

 
 int sqlite3_busy_handler(sqlite3*,int(*)(void*,int),void*);
 */

/**
 * SQLITE_API int sqlite3_busy_handler(sqlite3*,int(*)(void*,int),void*);
 * param1 哪个数据库需要设置busy_handler
 * param2 需要回调的busy handler，调用次函数时，需要传参，是sqlite3_busy_handler第三个参数
 * param3 int参数代表锁事件，该函数被调用次数，如果返回为0，不会再次访问数据库，返回非0，将不断尝试访问数据库。
 * 当获取不到锁时，会执行回调函数的次数以此来延时，等待其他线程等操作完数据库，这样获得操作数据库。
 */
- (void)setMaxBusyRetryTimeInterval:(NSTimeInterval)timeout {
    //默认_maxBusyRetryTimeInterval为2

    _maxBusyRetryTimeInterval = timeout;
    
    if (!_db) {
        return;
    }
    
    if (timeout > 0) {//处理的 handler 设置为FMDBDatabaseBusyHandler() 函数
        sqlite3_busy_handler(_db, &FMDBDatabaseBusyHandler, (__bridge void *)(self));
    }else {
        // 不使用任何busy handler处理
        sqlite3_busy_handler(_db, nil, nil);
    }
}

- (NSTimeInterval)maxBusyRetryTimeInterval {
    return _maxBusyRetryTimeInterval;
}


// we no longer make busyRetryTimeout public
// but for folks who don't bother noticing that the interface to FMDatabase changed,
// we'll still implement the method so they don't get suprise crashes
- (int)busyRetryTimeout {
    NSLog(@"%s:%d", __FUNCTION__, __LINE__);
    NSLog(@"FMDB: busyRetryTimeout no longer works, please use maxBusyRetryTimeInterval");
    return -1;
}

- (void)setBusyRetryTimeout:(int)i {
#pragma unused(i)
    NSLog(@"%s:%d", __FUNCTION__, __LINE__);
    NSLog(@"FMDB: setBusyRetryTimeout does nothing, please use setMaxBusyRetryTimeInterval:");
}

#pragma mark Result set functions

- (BOOL)hasOpenResultSets {
    return [_openResultSets count] > 0;
}

- (void)closeOpenResultSets {
    
    //Copy the set so we don't get mutation errors
    NSSet *openSetCopy = FMDBReturnAutoreleased([_openResultSets copy]);
    for (NSValue *rsInWrappedInATastyValueMeal in openSetCopy) {
        FMResultSet *rs = (FMResultSet *)[rsInWrappedInATastyValueMeal pointerValue];
        [rs setParentDB:nil];
        [rs close];
        [_openResultSets removeObject:rsInWrappedInATastyValueMeal];
    }
}

- (void)resultSetDidClose:(FMResultSet *)resultSet {
    NSValue *setValue = [NSValue valueWithNonretainedObject:resultSet];
    
    [_openResultSets removeObject:setValue];
}

#pragma mark Cached statements

- (void)clearCachedStatements {
    for (NSMutableSet *statements in [_cachedStatements objectEnumerator]) {
        for (FMStatement *statement in [statements allObjects]) {
            [statement close];
        }
    }
    [_cachedStatements removeAllObjects];
}

- (FMStatement*)cachedStatementForQuery:(NSString*)query {
    
    NSMutableSet* statements = [_cachedStatements objectForKey:query];
    
    return [[statements objectsPassingTest:^BOOL(FMStatement* statement, BOOL *stop) {
        
        *stop = ![statement inUse];
        return *stop;
        
    }] anyObject];
}


- (void)setCachedStatement:(FMStatement*)statement forQuery:(NSString*)query {
    NSParameterAssert(query);
    if (!query) {
        NSLog(@"API misuse, -[FMDatabase setCachedStatement:forQuery:] query must not be nil");
        return;
    }
    
    query = [query copy]; // in case we got handed in a mutable string...
    [statement setQuery:query];
    
    NSMutableSet* statements = [_cachedStatements objectForKey:query];
    if (!statements) {
        statements = [NSMutableSet set];
    }
    
    [statements addObject:statement];
    
    [_cachedStatements setObject:statements forKey:query];
    
    FMDBRelease(query);
}

#pragma mark Key routines

- (BOOL)rekey:(NSString*)key {
    NSData *keyData = [NSData dataWithBytes:(void *)[key UTF8String] length:(NSUInteger)strlen([key UTF8String])];
    
    return [self rekeyWithData:keyData];
}

- (BOOL)rekeyWithData:(NSData *)keyData {
#ifdef SQLITE_HAS_CODEC
    if (!keyData) {
        return NO;
    }
    
    int rc = sqlite3_rekey(_db, [keyData bytes], (int)[keyData length]);
    
    if (rc != SQLITE_OK) {
        NSLog(@"error on rekey: %d", rc);
        NSLog(@"%@", [self lastErrorMessage]);
    }
    
    return (rc == SQLITE_OK);
#else
#pragma unused(keyData)
    return NO;
#endif
}

- (BOOL)setKey:(NSString*)key {
    NSData *keyData = [NSData dataWithBytes:[key UTF8String] length:(NSUInteger)strlen([key UTF8String])];
    
    return [self setKeyWithData:keyData];
}

- (BOOL)setKeyWithData:(NSData *)keyData {
#ifdef SQLITE_HAS_CODEC
    if (!keyData) {
        return NO;
    }
    
    int rc = sqlite3_key(_db, [keyData bytes], (int)[keyData length]);
    
    return (rc == SQLITE_OK);
#else
#pragma unused(keyData)
    return NO;
#endif
}

#pragma mark Date routines

+ (NSDateFormatter *)storeableDateFormat:(NSString *)format {
    
    NSDateFormatter *result = FMDBReturnAutoreleased([[NSDateFormatter alloc] init]);
    result.dateFormat = format;
    result.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    result.locale = FMDBReturnAutoreleased([[NSLocale alloc] initWithLocaleIdentifier:@"en_US"]);
    return result;
}


- (BOOL)hasDateFormatter {
    return _dateFormat != nil;
}

- (void)setDateFormat:(NSDateFormatter *)format {
    FMDBAutorelease(_dateFormat);
    _dateFormat = FMDBReturnRetained(format);
}

- (NSDate *)dateFromString:(NSString *)s {
    return [_dateFormat dateFromString:s];
}

- (NSString *)stringFromDate:(NSDate *)date {
    return [_dateFormat stringFromDate:date];
}

#pragma mark State of database

- (BOOL)goodConnection {
    
    //1、数据库是否打开
    if (!_isOpen) {
        return NO;
    }
    
    //2、尝试一个简单的 SELECT 语句并确认成功
#ifdef SQLCIPHER_CRYPTO
    FMResultSet *rs = [self executeQuery:@"PRAGMA cipher_version"];
    if ([rs next]) {
        NSLog(@"SQLCipher version: %@", rs.resultDictionary[@"cipher_version"]);
        [rs close];
        return YES;
    }
#else
    FMResultSet *rs = [self executeQuery:@"select name from sqlite_master where type='table'"];
    if (rs) {
        [rs close];
        return YES;
    }
#endif
    return NO;
}

- (void)warnInUse {
    NSLog(@"The FMDatabase %@ is currently in use.", self);
    
#ifndef NS_BLOCK_ASSERTIONS
    if (_crashOnErrors) {
        NSAssert(false, @"The FMDatabase %@ is currently in use.", self);
        abort();
    }
#endif
}

- (BOOL)databaseExists {
    
    if (!_isOpen) {
        
        NSLog(@"The FMDatabase %@ is not open.", self);
        
#ifndef NS_BLOCK_ASSERTIONS
        if (_crashOnErrors) {
            NSAssert(false, @"The FMDatabase %@ is not open.", self);
            abort();
        }
#endif
        
        return NO;
    }
    
    return YES;
}

#pragma mark Error routines

- (NSString *)lastErrorMessage {
    return [NSString stringWithUTF8String:sqlite3_errmsg(_db)];
}

- (BOOL)hadError {
    int lastErrCode = [self lastErrorCode];
    
    return (lastErrCode > SQLITE_OK && lastErrCode < SQLITE_ROW);
}

- (int)lastErrorCode {
    return sqlite3_errcode(_db);
}

- (int)lastExtendedErrorCode {
    return sqlite3_extended_errcode(_db);
}

- (NSError*)errorWithMessage:(NSString *)message {
    NSDictionary* errorMessage = [NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
    
    return [NSError errorWithDomain:@"FMDatabase" code:sqlite3_errcode(_db) userInfo:errorMessage];
}

- (NSError*)lastError {
    return [self errorWithMessage:[self lastErrorMessage]];
}

#pragma mark Update information routines

- (sqlite_int64)lastInsertRowId {
    
    if (_isExecutingStatement) {
        [self warnInUse];
        return NO;
    }
    
    _isExecutingStatement = YES;
    
    sqlite_int64 ret = sqlite3_last_insert_rowid(_db);
    
    _isExecutingStatement = NO;
    
    return ret;
}

- (int)changes {
    if (_isExecutingStatement) {
        [self warnInUse];
        return 0;
    }
    
    _isExecutingStatement = YES;
    
    int ret = sqlite3_changes(_db);
    
    _isExecutingStatement = NO;
    
    return ret;
}

#pragma mark SQL manipulation

- (void)bindObject:(id)obj toColumn:(int)idx inStatement:(sqlite3_stmt*)pStmt {
    
    if ((!obj) || ((NSNull *)obj == [NSNull null])) {
        sqlite3_bind_null(pStmt, idx);
    }
    
    // FIXME - someday check the return codes on these binds.
    else if ([obj isKindOfClass:[NSData class]]) {
        const void *bytes = [obj bytes];
        if (!bytes) {
            // it's an empty NSData object, aka [NSData data].
            // Don't pass a NULL pointer, or sqlite will bind a SQL null instead of a blob.
            bytes = "";
        }
        sqlite3_bind_blob(pStmt, idx, bytes, (int)[obj length], SQLITE_STATIC);
    }
    else if ([obj isKindOfClass:[NSDate class]]) {
        if (self.hasDateFormatter)
            sqlite3_bind_text(pStmt, idx, [[self stringFromDate:obj] UTF8String], -1, SQLITE_STATIC);
        else
            sqlite3_bind_double(pStmt, idx, [obj timeIntervalSince1970]);
    }
    else if ([obj isKindOfClass:[NSNumber class]]) {
        
        if (strcmp([obj objCType], @encode(char)) == 0) {
            sqlite3_bind_int(pStmt, idx, [obj charValue]);
        }
        else if (strcmp([obj objCType], @encode(unsigned char)) == 0) {
            sqlite3_bind_int(pStmt, idx, [obj unsignedCharValue]);
        }
        else if (strcmp([obj objCType], @encode(short)) == 0) {
            sqlite3_bind_int(pStmt, idx, [obj shortValue]);
        }
        else if (strcmp([obj objCType], @encode(unsigned short)) == 0) {
            sqlite3_bind_int(pStmt, idx, [obj unsignedShortValue]);
        }
        else if (strcmp([obj objCType], @encode(int)) == 0) {
            sqlite3_bind_int(pStmt, idx, [obj intValue]);
        }
        else if (strcmp([obj objCType], @encode(unsigned int)) == 0) {
            sqlite3_bind_int64(pStmt, idx, (long long)[obj unsignedIntValue]);
        }
        else if (strcmp([obj objCType], @encode(long)) == 0) {
            sqlite3_bind_int64(pStmt, idx, [obj longValue]);
        }
        else if (strcmp([obj objCType], @encode(unsigned long)) == 0) {
            sqlite3_bind_int64(pStmt, idx, (long long)[obj unsignedLongValue]);
        }
        else if (strcmp([obj objCType], @encode(long long)) == 0) {
            sqlite3_bind_int64(pStmt, idx, [obj longLongValue]);
        }
        else if (strcmp([obj objCType], @encode(unsigned long long)) == 0) {
            sqlite3_bind_int64(pStmt, idx, (long long)[obj unsignedLongLongValue]);
        }
        else if (strcmp([obj objCType], @encode(float)) == 0) {
            sqlite3_bind_double(pStmt, idx, [obj floatValue]);
        }
        else if (strcmp([obj objCType], @encode(double)) == 0) {
            sqlite3_bind_double(pStmt, idx, [obj doubleValue]);
        }
        else if (strcmp([obj objCType], @encode(BOOL)) == 0) {
            sqlite3_bind_int(pStmt, idx, ([obj boolValue] ? 1 : 0));
        }
        else {
            sqlite3_bind_text(pStmt, idx, [[obj description] UTF8String], -1, SQLITE_STATIC);
        }
    }
    else {
        sqlite3_bind_text(pStmt, idx, [[obj description] UTF8String], -1, SQLITE_STATIC);
    }
}

- (void)extractSQL:(NSString *)sql argumentsList:(va_list)args intoString:(NSMutableString *)cleanedSQL arguments:(NSMutableArray *)arguments {
    
    NSUInteger length = [sql length];
    unichar last = '\0';
    for (NSUInteger i = 0; i < length; ++i) {
        id arg = nil;
        unichar current = [sql characterAtIndex:i];
        unichar add = current;
        if (last == '%') {
            switch (current) {
                case '@':
                    arg = va_arg(args, id);
                    break;
                case 'c':
                    // warning: second argument to 'va_arg' is of promotable type 'char'; this va_arg has undefined behavior because arguments will be promoted to 'int'
                    arg = [NSString stringWithFormat:@"%c", va_arg(args, int)];
                    break;
                case 's':
                    arg = [NSString stringWithUTF8String:va_arg(args, char*)];
                    break;
                case 'd':
                case 'D':
                case 'i':
                    arg = [NSNumber numberWithInt:va_arg(args, int)];
                    break;
                case 'u':
                case 'U':
                    arg = [NSNumber numberWithUnsignedInt:va_arg(args, unsigned int)];
                    break;
                case 'h':
                    i++;
                    if (i < length && [sql characterAtIndex:i] == 'i') {
                        //  warning: second argument to 'va_arg' is of promotable type 'short'; this va_arg has undefined behavior because arguments will be promoted to 'int'
                        arg = [NSNumber numberWithShort:(short)(va_arg(args, int))];
                    }
                    else if (i < length && [sql characterAtIndex:i] == 'u') {
                        // warning: second argument to 'va_arg' is of promotable type 'unsigned short'; this va_arg has undefined behavior because arguments will be promoted to 'int'
                        arg = [NSNumber numberWithUnsignedShort:(unsigned short)(va_arg(args, uint))];
                    }
                    else {
                        i--;
                    }
                    break;
                case 'q':
                    i++;
                    if (i < length && [sql characterAtIndex:i] == 'i') {
                        arg = [NSNumber numberWithLongLong:va_arg(args, long long)];
                    }
                    else if (i < length && [sql characterAtIndex:i] == 'u') {
                        arg = [NSNumber numberWithUnsignedLongLong:va_arg(args, unsigned long long)];
                    }
                    else {
                        i--;
                    }
                    break;
                case 'f':
                    arg = [NSNumber numberWithDouble:va_arg(args, double)];
                    break;
                case 'g':
                    // warning: second argument to 'va_arg' is of promotable type 'float'; this va_arg has undefined behavior because arguments will be promoted to 'double'
                    arg = [NSNumber numberWithFloat:(float)(va_arg(args, double))];
                    break;
                case 'l':
                    i++;
                    if (i < length) {
                        unichar next = [sql characterAtIndex:i];
                        if (next == 'l') {
                            i++;
                            if (i < length && [sql characterAtIndex:i] == 'd') {
                                //%lld
                                arg = [NSNumber numberWithLongLong:va_arg(args, long long)];
                            }
                            else if (i < length && [sql characterAtIndex:i] == 'u') {
                                //%llu
                                arg = [NSNumber numberWithUnsignedLongLong:va_arg(args, unsigned long long)];
                            }
                            else {
                                i--;
                            }
                        }
                        else if (next == 'd') {
                            //%ld
                            arg = [NSNumber numberWithLong:va_arg(args, long)];
                        }
                        else if (next == 'u') {
                            //%lu
                            arg = [NSNumber numberWithUnsignedLong:va_arg(args, unsigned long)];
                        }
                        else {
                            i--;
                        }
                    }
                    else {
                        i--;
                    }
                    break;
                default:
                    // something else that we can't interpret. just pass it on through like normal
                    break;
            }
        }
        else if (current == '%') {
            // percent sign; skip this character
            add = '\0';
        }
        
        if (arg != nil) {
            [cleanedSQL appendString:@"?"];
            [arguments addObject:arg];
        }
        else if (add == (unichar)'@' && last == (unichar) '%') {
            [cleanedSQL appendFormat:@"NULL"];
        }
        else if (add != '\0') {
            [cleanedSQL appendFormat:@"%C", add];
        }
        last = current;
    }
}

#pragma mark Execute queries

- (FMResultSet *)executeQuery:(NSString *)sql withParameterDictionary:(NSDictionary *)arguments {
    return [self executeQuery:sql withArgumentsInArray:nil orDictionary:arguments orVAList:nil];
}

// https://www.cnblogs.com/guohai-stronger/p/9246653.html
/**
 * @param sql 代表我们要查询的sql语句
 * @param arrayArgs 代表数组类型的参数
 *  如：FMResultSet *resultSet = [_db executeQuery:@"SELECT * FROM t_student WHERE age > ?" withArgumentsInArray:@[@25]];
 * @param dictionaryArgs 代表字典类型的参数
 *  如：FMResultSet *resultSet = [_db executeQuery:@"SELECT * FROM t_student WHERE age > :age" withParameterDictionary:@{@"age":@25}];
 * @param args 代表可变类型的参数
 *  如：FMResultSet *resultSet = [_db executeQuery:@"SELECT * FROM t_student WHERE age > ?",@(20)];
 */
- (FMResultSet *)executeQuery:(NSString *)sql withArgumentsInArray:(NSArray*)arrayArgs orDictionary:(NSDictionary *)dictionaryArgs orVAList:(va_list)args {
    
    if (![self databaseExists]) {//判断数据库是否存在
        return 0x00;
    }
    
    if (_isExecutingStatement) {//判断数据库是否已经在使用当中
        [self warnInUse];
        return 0x00;
    }
    
    _isExecutingStatement = YES;
    
    int rc                  = 0x00;
    sqlite3_stmt *pStmt     = 0x00;
    FMStatement *statement  = 0x00;
    FMResultSet *rs         = 0x00;
    
    if (_traceExecution && sql) {//打印sql语句
        NSLog(@"%@ executeQuery: %@", self, sql);
    }
    
    if (_shouldCacheStatements) {//获取缓存数据
        statement = [self cachedStatementForQuery:sql];
        pStmt = statement ? [statement statement] : 0x00;
        [statement reset];
    }
    
    if (!pStmt) {//没有缓存数据，直接查询数据库
        
        //对sql语句进行预处理，生成预处理过的“sql语句”pStmt。
        rc = sqlite3_prepare_v2(_db, [sql UTF8String], -1, &pStmt, 0);
        
        if (SQLITE_OK != rc) {//出错处理
            if (_logsErrors) {
                NSLog(@"DB Error: %d \"%@\"", [self lastErrorCode], [self lastErrorMessage]);
                NSLog(@"DB Query: %@", sql);
                NSLog(@"DB Path: %@", _databasePath);
            }
            
            if (_crashOnErrors) {
                NSAssert(false, @"DB Error: %d \"%@\"", [self lastErrorCode], [self lastErrorMessage]);
                abort();
            }
            
            sqlite3_finalize(pStmt);
            _isExecutingStatement = NO;
            return nil;
        }
    }
    
    id obj;
    int idx = 0;
    int queryCount = sqlite3_bind_parameter_count(pStmt); // pointed out by Dominic Yu (thanks!)
    
    // If dictionaryArgs is passed in, that means we are using sqlite's named parameter support
    //对dictionaryArgs参数的处理，类似于下面":age"参数形式
    if (dictionaryArgs) {
        
        for (NSString *dictionaryKey in [dictionaryArgs allKeys]) {
            
            // Prefix the key with a colon.
            NSString *parameterName = [[NSString alloc] initWithFormat:@":%@", dictionaryKey];
            
            if (_traceExecution) {
                NSLog(@"%@ = %@", parameterName, [dictionaryArgs objectForKey:dictionaryKey]);
            }
            
            // Get the index for the parameter name.
            int namedIdx = sqlite3_bind_parameter_index(pStmt, [parameterName UTF8String]);
            
            FMDBRelease(parameterName);
            
            if (namedIdx > 0) {
                // Standard binding from here.
                [self bindObject:[dictionaryArgs objectForKey:dictionaryKey] toColumn:namedIdx inStatement:pStmt];
                // increment the binding count, so our check below works out
                idx++;
            }
            else {
                NSLog(@"Could not find index for %@", dictionaryKey);
            }
        }
    } else {//对于arrayArgs参数和不定参数的处理，类似于"?"参数形式
        
        while (idx < queryCount) {
            
            if (arrayArgs && idx < (int)[arrayArgs count]) {
                obj = [arrayArgs objectAtIndex:(NSUInteger)idx];
            }else if (args) {//不定参数形式
                obj = va_arg(args, id);
            }else {
                //We ran out of arguments
                break;
            }
            
            if (_traceExecution) {
                if ([obj isKindOfClass:[NSData class]]) {
                    NSLog(@"data: %ld bytes", (unsigned long)[(NSData*)obj length]);
                }
                else {
                    NSLog(@"obj: %@", obj);
                }
            }
            
            idx++;
            
            [self bindObject:obj toColumn:idx inStatement:pStmt];
        }
    }
    
    if (idx != queryCount) {//如果绑定的参数数目不对，则进行出错处理
        NSLog(@"Error: the bind count is not correct for the # of variables (executeQuery)");
        sqlite3_finalize(pStmt);
        _isExecutingStatement = NO;
        return nil;
    }
    
    FMDBRetain(statement); // to balance the release below
    
    if (!statement) {//生成FMStatement对象
        statement = [[FMStatement alloc] init];
        [statement setStatement:pStmt];
        
        //缓存的处理，key为sql语句，值为statement
        if (_shouldCacheStatements && sql) {
            [self setCachedStatement:statement forQuery:sql];
        }
    }
    
    // the statement gets closed in rs's dealloc or [rs close];
    rs = [FMResultSet resultSetWithStatement:statement usingParentDatabase:self];
    [rs setQuery:sql];
    
    NSValue *openResultSet = [NSValue valueWithNonretainedObject:rs];
    [_openResultSets addObject:openResultSet];
    
    [statement setUseCount:[statement useCount] + 1];
    
    FMDBRelease(statement);
    
    _isExecutingStatement = NO;
    
    return rs;
}

- (FMResultSet *)executeQuery:(NSString*)sql, ... {
    va_list args;
    va_start(args, sql);
    //关键语句
    id result = [self executeQuery:sql withArgumentsInArray:nil orDictionary:nil orVAList:args];
    
    va_end(args);
    return result;
}

- (FMResultSet *)executeQueryWithFormat:(NSString*)format, ... {
    va_list args;
    va_start(args, format);
    
    NSMutableString *sql = [NSMutableString stringWithCapacity:[format length]];
    NSMutableArray *arguments = [NSMutableArray array];
    [self extractSQL:format argumentsList:args intoString:sql arguments:arguments];
    
    va_end(args);
    
    return [self executeQuery:sql withArgumentsInArray:arguments];
}

- (FMResultSet *)executeQuery:(NSString *)sql withArgumentsInArray:(NSArray *)arguments {
    return [self executeQuery:sql withArgumentsInArray:arguments orDictionary:nil orVAList:nil];
}

- (FMResultSet *)executeQuery:(NSString *)sql values:(NSArray *)values error:(NSError * __autoreleasing *)error {
    FMResultSet *rs = [self executeQuery:sql withArgumentsInArray:values orDictionary:nil orVAList:nil];
    if (!rs && error) {
        *error = [self lastError];
    }
    return rs;
}

- (FMResultSet *)executeQuery:(NSString*)sql withVAList:(va_list)args {
    return [self executeQuery:sql withArgumentsInArray:nil orDictionary:nil orVAList:args];
}

#pragma mark Execute updates

- (BOOL)executeUpdate:(NSString*)sql error:(NSError * _Nullable __autoreleasing *)outErr withArgumentsInArray:(NSArray*)arrayArgs orDictionary:(NSDictionary *)dictionaryArgs orVAList:(va_list)args {
    if (![self databaseExists]) {//数据库是否存在
        return NO;
    }
    if (_isExecutingStatement) {//正在执行 Sql
        [self warnInUse];
        return NO;
    }
    
    _isExecutingStatement = YES;
    
    int rc                   = 0x00;
    sqlite3_stmt *pStmt      = 0x00;
    FMStatement *cachedStmt  = 0x00;
    
    if (_traceExecution && sql) {
        NSLog(@"%@ executeUpdate: %@", self, sql);
    }
    
    if (_shouldCacheStatements) {
        cachedStmt = [self cachedStatementForQuery:sql];
        pStmt = cachedStmt ? [cachedStmt statement] : 0x00;
        [cachedStmt reset];
    }
    
    if (!pStmt) {
        rc = sqlite3_prepare_v2(_db, [sql UTF8String], -1, &pStmt, 0);
        
        if (SQLITE_OK != rc) {
            if (_logsErrors) {
                NSLog(@"DB Error: %d \"%@\"", [self lastErrorCode], [self lastErrorMessage]);
                NSLog(@"DB Query: %@", sql);
                NSLog(@"DB Path: %@", _databasePath);
            }
            
            if (_crashOnErrors) {
                NSAssert(false, @"DB Error: %d \"%@\"", [self lastErrorCode], [self lastErrorMessage]);
                abort();
            }
            
            if (outErr) {
                *outErr = [self errorWithMessage:[NSString stringWithUTF8String:sqlite3_errmsg(_db)]];
            }
            
            sqlite3_finalize(pStmt);
            
            _isExecutingStatement = NO;
            return NO;
        }
    }
    
    id obj;
    int idx = 0;
    int queryCount = sqlite3_bind_parameter_count(pStmt);
    
    // If dictionaryArgs is passed in, that means we are using sqlite's named parameter support
    if (dictionaryArgs) {
        
        for (NSString *dictionaryKey in [dictionaryArgs allKeys]) {
            
            // Prefix the key with a colon.
            NSString *parameterName = [[NSString alloc] initWithFormat:@":%@", dictionaryKey];
            
            if (_traceExecution) {
                NSLog(@"%@ = %@", parameterName, [dictionaryArgs objectForKey:dictionaryKey]);
            }
            // Get the index for the parameter name.
            int namedIdx = sqlite3_bind_parameter_index(pStmt, [parameterName UTF8String]);
            
            FMDBRelease(parameterName);
            
            if (namedIdx > 0) {
                // Standard binding from here.
                [self bindObject:[dictionaryArgs objectForKey:dictionaryKey] toColumn:namedIdx inStatement:pStmt];
                
                // increment the binding count, so our check below works out
                idx++;
            }else {
                NSString *message = [NSString stringWithFormat:@"Could not find index for %@", dictionaryKey];
                
                if (_logsErrors) {
                    NSLog(@"%@", message);
                }
                if (outErr) {
                    *outErr = [self errorWithMessage:message];
                }
            }
        }
    }
    else {
        
        while (idx < queryCount) {
            
            if (arrayArgs && idx < (int)[arrayArgs count]) {
                obj = [arrayArgs objectAtIndex:(NSUInteger)idx];
            }
            else if (args) {
                obj = va_arg(args, id);
            }
            else {
                //We ran out of arguments
                break;
            }
            
            if (_traceExecution) {
                if ([obj isKindOfClass:[NSData class]]) {
                    NSLog(@"data: %ld bytes", (unsigned long)[(NSData*)obj length]);
                }
                else {
                    NSLog(@"obj: %@", obj);
                }
            }
            
            idx++;
            
            [self bindObject:obj toColumn:idx inStatement:pStmt];
        }
    }
    
    
    if (idx != queryCount) {
        NSString *message = [NSString stringWithFormat:@"Error: the bind count (%d) is not correct for the # of variables in the query (%d) (%@) (executeUpdate)", idx, queryCount, sql];
        if (_logsErrors) {
            NSLog(@"%@", message);
        }
        if (outErr) {
            *outErr = [self errorWithMessage:message];
        }
        
        sqlite3_finalize(pStmt);
        _isExecutingStatement = NO;
        return NO;
    }
    
    /* Call sqlite3_step() to run the virtual machine. Since the SQL being
     ** executed is not a SELECT statement, we assume no data will be returned.
     */
    
    rc      = sqlite3_step(pStmt);
    
    if (SQLITE_DONE == rc) {
        // all is well, let's return.
    }
    else if (SQLITE_INTERRUPT == rc) {
        if (_logsErrors) {
            NSLog(@"Error calling sqlite3_step. Query was interrupted (%d: %s) SQLITE_INTERRUPT", rc, sqlite3_errmsg(_db));
            NSLog(@"DB Query: %@", sql);
        }
    }
    else if (rc == SQLITE_ROW) {
        NSString *message = [NSString stringWithFormat:@"A executeUpdate is being called with a query string '%@'", sql];
        if (_logsErrors) {
            NSLog(@"%@", message);
            NSLog(@"DB Query: %@", sql);
        }
        if (outErr) {
            *outErr = [self errorWithMessage:message];
        }
    }
    else {
        if (outErr) {
            *outErr = [self errorWithMessage:[NSString stringWithUTF8String:sqlite3_errmsg(_db)]];
        }
        
        if (SQLITE_ERROR == rc) {
            if (_logsErrors) {
                NSLog(@"Error calling sqlite3_step (%d: %s) SQLITE_ERROR", rc, sqlite3_errmsg(_db));
                NSLog(@"DB Query: %@", sql);
            }
        }
        else if (SQLITE_MISUSE == rc) {
            // uh oh.
            if (_logsErrors) {
                NSLog(@"Error calling sqlite3_step (%d: %s) SQLITE_MISUSE", rc, sqlite3_errmsg(_db));
                NSLog(@"DB Query: %@", sql);
            }
        }
        else {
            // wtf?
            if (_logsErrors) {
                NSLog(@"Unknown error calling sqlite3_step (%d: %s) eu", rc, sqlite3_errmsg(_db));
                NSLog(@"DB Query: %@", sql);
            }
        }
    }
    
    if (_shouldCacheStatements && !cachedStmt) {
        cachedStmt = [[FMStatement alloc] init];
        
        [cachedStmt setStatement:pStmt];
        
        [self setCachedStatement:cachedStmt forQuery:sql];
        
        FMDBRelease(cachedStmt);
    }
    
    int closeErrorCode;
    
    if (cachedStmt) {
        [cachedStmt setUseCount:[cachedStmt useCount] + 1];
        closeErrorCode = sqlite3_reset(pStmt);
    }
    else {
        /* Finalize the virtual machine. This releases all memory and other
         ** resources allocated by the sqlite3_prepare() call above.
         */
        closeErrorCode = sqlite3_finalize(pStmt);
    }
    
    if (closeErrorCode != SQLITE_OK) {
        if (_logsErrors) {
            NSLog(@"Unknown error finalizing or resetting statement (%d: %s)", closeErrorCode, sqlite3_errmsg(_db));
            NSLog(@"DB Query: %@", sql);
        }
    }
    
    _isExecutingStatement = NO;
    return (rc == SQLITE_DONE || rc == SQLITE_OK);
}


- (BOOL)executeUpdate:(NSString*)sql, ... {
    va_list args;
    va_start(args, sql);
    BOOL result = [self executeUpdate:sql error:nil withArgumentsInArray:nil orDictionary:nil orVAList:args];
    va_end(args);
    return result;
}

- (BOOL)executeUpdate:(NSString*)sql withArgumentsInArray:(NSArray *)arguments {
    return [self executeUpdate:sql error:nil withArgumentsInArray:arguments orDictionary:nil orVAList:nil];
}

- (BOOL)executeUpdate:(NSString*)sql values:(NSArray *)values error:(NSError * __autoreleasing *)error {
    return [self executeUpdate:sql error:error withArgumentsInArray:values orDictionary:nil orVAList:nil];
}

- (BOOL)executeUpdate:(NSString*)sql withParameterDictionary:(NSDictionary *)arguments {
    return [self executeUpdate:sql error:nil withArgumentsInArray:nil orDictionary:arguments orVAList:nil];
}

- (BOOL)executeUpdate:(NSString*)sql withVAList:(va_list)args {
    return [self executeUpdate:sql error:nil withArgumentsInArray:nil orDictionary:nil orVAList:args];
}

- (BOOL)executeUpdateWithFormat:(NSString*)format, ... {
    va_list args;
    va_start(args, format);
    
    NSMutableString *sql      = [NSMutableString stringWithCapacity:[format length]];
    NSMutableArray *arguments = [NSMutableArray array];
    
    [self extractSQL:format argumentsList:args intoString:sql arguments:arguments];
    
    va_end(args);
    
    return [self executeUpdate:sql withArgumentsInArray:arguments];
}


int FMDBExecuteBulkSQLCallback(void *theBlockAsVoid, int columns, char **values, char **names); // shhh clang.
int FMDBExecuteBulkSQLCallback(void *theBlockAsVoid, int columns, char **values, char **names) {
    
    if (!theBlockAsVoid) {
        return SQLITE_OK;
    }
    
    int (^execCallbackBlock)(NSDictionary *resultsDictionary) = (__bridge int (^)(NSDictionary *__strong))(theBlockAsVoid);
    
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithCapacity:(NSUInteger)columns];
    
    for (NSInteger i = 0; i < columns; i++) {
        NSString *key = [NSString stringWithUTF8String:names[i]];
        id value = values[i] ? [NSString stringWithUTF8String:values[i]] : [NSNull null];
        value = value ? value : [NSNull null];
        [dictionary setObject:value forKey:key];
    }
    
    return execCallbackBlock(dictionary);
}

- (BOOL)executeStatements:(NSString *)sql {
    return [self executeStatements:sql withResultBlock:nil];
}

- (BOOL)executeStatements:(NSString *)sql withResultBlock:(__attribute__((noescape)) FMDBExecuteStatementsCallbackBlock)block {
    
    int rc;
    char *errmsg = nil;
    
    rc = sqlite3_exec([self sqliteHandle], [sql UTF8String], block ? FMDBExecuteBulkSQLCallback : nil, (__bridge void *)(block), &errmsg);
    
    if (errmsg && [self logsErrors]) {
        NSLog(@"Error inserting batch: %s", errmsg);
    }
    if (errmsg) {
        sqlite3_free(errmsg);
    }
    
    return (rc == SQLITE_OK);
}

- (BOOL)executeUpdate:(NSString*)sql withErrorAndBindings:(NSError * _Nullable __autoreleasing *)outErr, ... {
    
    va_list args;
    va_start(args, outErr);
    
    BOOL result = [self executeUpdate:sql error:outErr withArgumentsInArray:nil orDictionary:nil orVAList:args];
    
    va_end(args);
    return result;
}


#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (BOOL)update:(NSString*)sql withErrorAndBindings:(NSError * _Nullable __autoreleasing *)outErr, ... {
    va_list args;
    va_start(args, outErr);
    
    BOOL result = [self executeUpdate:sql error:outErr withArgumentsInArray:nil orDictionary:nil orVAList:args];
    
    va_end(args);
    return result;
}

#pragma clang diagnostic pop

#pragma mark 事务

/**
SQLite目前不允许嵌套事务。

可以使用BEGIN命令手动启动事务。这样启动的事务会在下一条COMMIT或ROLLBACK命令之前一直有效。但若数据库关闭 或出现错误且选用ROLLBACK冲突判定算法时，数据库也会ROLLBACK。


在SQLite 3.0.8 或更高版本中，事务可以是延迟的，即时的或者独占的。
“延迟的”即是说在数据库第一次被访问之前不获得锁。 这样就会延迟事务，BEGIN语句本身不做任何事情。
直到初次读取或访问数据库时才获取锁。对数据库的初次读取创建一个SHARED锁 ，初次写入创建一个RESERVED锁。
由于锁的获取被延迟到第一次需要时，别的线程或进程可以在当前线程执行BEGIN语句之后创建另外的事务 写入数据库。

若事务是即时的，则执行BEGIN命令后立即获取RESERVED锁，而不等数据库被使用。在执行BEGIN IMMEDIATE之后， 你可以确保其它的线程或进程不能写入数据库或执行BEGIN IMMEDIATE或BEGIN EXCLUSIVE. 但其它进程可以读取数据库。

独占事务在所有的数据库获取EXCLUSIVE锁，在执行BEGIN EXCLUSIVE之后，你可以确保在当前事务结束前没有任何其它线程或进程 能够读写数据库。

 
BEGIN 或 START TRANSACTION 显式地开启一个事务；

COMMIT 也可以使用 COMMIT WORK，不过二者是等价的。COMMIT 会提交事务，并使已对数据库进行的所有修改成为永久性的；

ROLLBACK 也可以使用 ROLLBACK WORK，不过二者是等价的。回滚会结束用户的事务，并撤销正在进行的所有未提交的修改；

SAVEPOINT identifier，SAVEPOINT 允许在事务中创建一个保存点，一个事务中可以有多个 SAVEPOINT；

RELEASE SAVEPOINT identifier 删除一个事务的保存点，当没有指定的保存点时，执行该语句会抛出一个异常；

ROLLBACK TO identifier 把事务回滚到标记点；

SET TRANSACTION 用来设置事务的隔离级别。InnoDB 存储引擎提供事务的隔离级别有READ UNCOMMITTED、READ COMMITTED、REPEATABLE READ 和 SERIALIZABLE。]
 
 */

//事务回滚
- (BOOL)rollback {
    BOOL b = [self executeUpdate:@"rollback transaction"];
    if (b) {
        _isInTransaction = NO;
    }
    return b;
}

//事务确认
- (BOOL)commit {
    BOOL b =  [self executeUpdate:@"commit transaction"];
    if (b) {
        _isInTransaction = NO;
    }
    return b;
}

- (BOOL)beginTransaction {//默认开始互斥事务
    BOOL b = [self executeUpdate:@"begin exclusive transaction"];
    if (b) {
        _isInTransaction = YES;
    }
    return b;
}

//开始一个延迟的事务
- (BOOL)beginDeferredTransaction {
    BOOL b = [self executeUpdate:@"begin deferred transaction"];
    if (b) {
        _isInTransaction = YES;
    }
    return b;
}

//立即开启事务
- (BOOL)beginImmediateTransaction {
    BOOL b = [self executeUpdate:@"begin immediate transaction"];
    if (b) {
        _isInTransaction = YES;
    }
    return b;
}

//开始互斥事务
- (BOOL)beginExclusiveTransaction {
    BOOL b = [self executeUpdate:@"begin exclusive transaction"];
    if (b) {
        _isInTransaction = YES;
    }
    return b;
}

- (BOOL)inTransaction {
    return _isInTransaction;
}

- (BOOL)interrupt{
    if (_db) {
        sqlite3_interrupt([self sqliteHandle]);
        return YES;
    }
    return NO;
}

static NSString *FMDBEscapeSavePointName(NSString *savepointName) {
    return [savepointName stringByReplacingOccurrencesOfString:@"'" withString:@"''"];
}

// 设置保存点： savepoint a
- (BOOL)startSavePointWithName:(NSString*)name error:(NSError * _Nullable __autoreleasing *)outErr {
#if SQLITE_VERSION_NUMBER >= 3007000
    NSParameterAssert(name);
    
    NSString *sql = [NSString stringWithFormat:@"savepoint '%@';", FMDBEscapeSavePointName(name)];
    
    return [self executeUpdate:sql error:outErr withArgumentsInArray:nil orDictionary:nil orVAList:nil];
#else
    NSString *errorMessage = NSLocalizedStringFromTable(@"Save point functions require SQLite 3.7", @"FMDB", nil);
    if (self.logsErrors) NSLog(@"%@", errorMessage);
    return NO;
#endif
}

//刪除保存点： release savepoint a
- (BOOL)releaseSavePointWithName:(NSString*)name error:(NSError * _Nullable __autoreleasing *)outErr {
#if SQLITE_VERSION_NUMBER >= 3007000
    NSParameterAssert(name);
    
    NSString *sql = [NSString stringWithFormat:@"release savepoint '%@';", FMDBEscapeSavePointName(name)];

    return [self executeUpdate:sql error:outErr withArgumentsInArray:nil orDictionary:nil orVAList:nil];
#else
    NSString *errorMessage = NSLocalizedStringFromTable(@"Save point functions require SQLite 3.7", @"FMDB", nil);
    if (self.logsErrors) NSLog(@"%@", errorMessage);
    return NO;
#endif
}

//回滚到保存点：rollback transaction to savepoint a
- (BOOL)rollbackToSavePointWithName:(NSString*)name error:(NSError * _Nullable __autoreleasing *)outErr {
#if SQLITE_VERSION_NUMBER >= 3007000
    NSParameterAssert(name);
    
    NSString *sql = [NSString stringWithFormat:@"rollback transaction to savepoint '%@';", FMDBEscapeSavePointName(name)];

    return [self executeUpdate:sql error:outErr withArgumentsInArray:nil orDictionary:nil orVAList:nil];
#else
    NSString *errorMessage = NSLocalizedStringFromTable(@"Save point functions require SQLite 3.7", @"FMDB", nil);
    if (self.logsErrors) NSLog(@"%@", errorMessage);
    return NO;
#endif
}

- (NSError*)inSavePoint:(__attribute__((noescape)) void (^)(BOOL *rollback))block {
#if SQLITE_VERSION_NUMBER >= 3007000
    static unsigned long savePointIdx = 0;
    
    NSString *name = [NSString stringWithFormat:@"dbSavePoint%ld", savePointIdx++];
    
    BOOL shouldRollback = NO;
    
    NSError *err = 0x00;
    
    if (![self startSavePointWithName:name error:&err]) {
        return err;
    }
    
    if (block) {
        block(&shouldRollback);
    }
    
    if (shouldRollback) {
        // We need to rollback and release this savepoint to remove it
        [self rollbackToSavePointWithName:name error:&err];
    }
    [self releaseSavePointWithName:name error:&err];
    
    return err;
#else
    NSString *errorMessage = NSLocalizedStringFromTable(@"Save point functions require SQLite 3.7", @"FMDB", nil);
    if (self.logsErrors) NSLog(@"%@", errorMessage);
    return [NSError errorWithDomain:@"FMDatabase" code:0 userInfo:@{NSLocalizedDescriptionKey : errorMessage}];
#endif
}

- (BOOL)checkpoint:(FMDBCheckpointMode)checkpointMode error:(NSError * __autoreleasing *)error {
    return [self checkpoint:checkpointMode name:nil logFrameCount:NULL checkpointCount:NULL error:error];
}

- (BOOL)checkpoint:(FMDBCheckpointMode)checkpointMode name:(NSString *)name error:(NSError * __autoreleasing *)error {
    return [self checkpoint:checkpointMode name:name logFrameCount:NULL checkpointCount:NULL error:error];
}

- (BOOL)checkpoint:(FMDBCheckpointMode)checkpointMode name:(NSString *)name logFrameCount:(int *)logFrameCount checkpointCount:(int *)checkpointCount error:(NSError * __autoreleasing *)error
{
    const char* dbName = [name UTF8String];
#if SQLITE_VERSION_NUMBER >= 3007006
    int err = sqlite3_wal_checkpoint_v2(_db, dbName, checkpointMode, logFrameCount, checkpointCount);
#else
    NSLog(@"sqlite3_wal_checkpoint_v2 unavailable before sqlite 3.7.6. Ignoring checkpoint mode: %d", mode);
    int err = sqlite3_wal_checkpoint(_db, dbName);
#endif
    if(err != SQLITE_OK) {
        if (error) {
            *error = [self lastError];
        }
        if (self.logsErrors) NSLog(@"%@", [self lastErrorMessage]);
        if (self.crashOnErrors) {
            NSAssert(false, @"%@", [self lastErrorMessage]);
            abort();
        }
        return NO;
    } else {
        return YES;
    }
}

#pragma mark Cache statements

- (BOOL)shouldCacheStatements {
    return _shouldCacheStatements;
}

- (void)setShouldCacheStatements:(BOOL)value {
    
    _shouldCacheStatements = value;
    
    if (_shouldCacheStatements && !_cachedStatements) {
        [self setCachedStatements:[NSMutableDictionary dictionary]];
    }
    
    if (!_shouldCacheStatements) {
        [self setCachedStatements:nil];
    }
}

#pragma mark Callback function

void FMDBBlockSQLiteCallBackFunction(sqlite3_context *context, int argc, sqlite3_value **argv); // -Wmissing-prototypes
void FMDBBlockSQLiteCallBackFunction(sqlite3_context *context, int argc, sqlite3_value **argv) {
#if ! __has_feature(objc_arc)
    void (^block)(sqlite3_context *context, int argc, sqlite3_value **argv) = (id)sqlite3_user_data(context);
#else
    void (^block)(sqlite3_context *context, int argc, sqlite3_value **argv) = (__bridge id)sqlite3_user_data(context);
#endif
    if (block) {
        @autoreleasepool {
            block(context, argc, argv);
        }
    }
}

// deprecated because "arguments" parameter is not maximum argument count, but actual argument count.

- (void)makeFunctionNamed:(NSString *)name maximumArguments:(int)arguments withBlock:(void (^)(void *context, int argc, void **argv))block {
    [self makeFunctionNamed:name arguments:arguments block:block];
}

- (void)makeFunctionNamed:(NSString *)name arguments:(int)arguments block:(void (^)(void *context, int argc, void **argv))block {
    
    if (!_openFunctions) {
        _openFunctions = [NSMutableSet new];
    }
    
    id b = FMDBReturnAutoreleased([block copy]);
    
    [_openFunctions addObject:b];
    
    /* I tried adding custom functions to release the block when the connection is destroyed- but they seemed to never be called, so we use _openFunctions to store the values instead. */
#if ! __has_feature(objc_arc)
    sqlite3_create_function([self sqliteHandle], [name UTF8String], arguments, SQLITE_UTF8, (void*)b, &FMDBBlockSQLiteCallBackFunction, 0x00, 0x00);
#else
    sqlite3_create_function([self sqliteHandle], [name UTF8String], arguments, SQLITE_UTF8, (__bridge void*)b, &FMDBBlockSQLiteCallBackFunction, 0x00, 0x00);
#endif
}

- (SqliteValueType)valueType:(void *)value {
    return sqlite3_value_type(value);
}

- (int)valueInt:(void *)value {
    return sqlite3_value_int(value);
}

- (long long)valueLong:(void *)value {
    return sqlite3_value_int64(value);
}

- (double)valueDouble:(void *)value {
    return sqlite3_value_double(value);
}

- (NSData *)valueData:(void *)value {
    const void *bytes = sqlite3_value_blob(value);
    int length = sqlite3_value_bytes(value);
    return bytes ? [NSData dataWithBytes:bytes length:(NSUInteger)length] : nil;
}

- (NSString *)valueString:(void *)value {
    const char *cString = (const char *)sqlite3_value_text(value);
    return cString ? [NSString stringWithUTF8String:cString] : nil;
}

- (void)resultNullInContext:(void *)context {
    sqlite3_result_null(context);
}

- (void)resultInt:(int) value context:(void *)context {
    sqlite3_result_int(context, value);
}

- (void)resultLong:(long long)value context:(void *)context {
    sqlite3_result_int64(context, value);
}

- (void)resultDouble:(double)value context:(void *)context {
    sqlite3_result_double(context, value);
}

- (void)resultData:(NSData *)data context:(void *)context {
    sqlite3_result_blob(context, data.bytes, (int)data.length, SQLITE_TRANSIENT);
}

- (void)resultString:(NSString *)value context:(void *)context {
    sqlite3_result_text(context, [value UTF8String], -1, SQLITE_TRANSIENT);
}

- (void)resultError:(NSString *)error context:(void *)context {
    sqlite3_result_error(context, [error UTF8String], -1);
}

- (void)resultErrorCode:(int)errorCode context:(void *)context {
    sqlite3_result_error_code(context, errorCode);
}

- (void)resultErrorNoMemoryInContext:(void *)context {
    sqlite3_result_error_nomem(context);
}

- (void)resultErrorTooBigInContext:(void *)context {
    sqlite3_result_error_toobig(context);
}

@end



@implementation FMStatement

#if ! __has_feature(objc_arc)
- (void)finalize {
    [self close];
    [super finalize];
}
#endif

- (void)dealloc {
    [self close];
    FMDBRelease(_query);
#if ! __has_feature(objc_arc)
    [super dealloc];
#endif
}

- (void)close {
    if (_statement) {
        sqlite3_finalize(_statement);
        _statement = 0x00;
    }
    
    _inUse = NO;
}

- (void)reset {
    if (_statement) {
        sqlite3_reset(_statement);
    }
    
    _inUse = NO;
}

- (NSString*)description {
    return [NSString stringWithFormat:@"%@ %ld hit(s) for query %@", [super description], _useCount, _query];
}

@end

