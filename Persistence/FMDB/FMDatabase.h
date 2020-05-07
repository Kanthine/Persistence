#import <Foundation/Foundation.h>
#import "FMResultSet.h"
#import "FMDatabasePool.h"

NS_ASSUME_NONNULL_BEGIN

#if ! __has_feature(objc_arc)
    #define FMDBAutorelease(__v) ([__v autorelease]);
    #define FMDBReturnAutoreleased FMDBAutorelease

    #define FMDBRetain(__v) ([__v retain]);
    #define FMDBReturnRetained FMDBRetain

    #define FMDBRelease(__v) ([__v release]);

    #define FMDBDispatchQueueRelease(__v) (dispatch_release(__v));
#else
    // -fobjc-arc
    #define FMDBAutorelease(__v)
    #define FMDBReturnAutoreleased(__v) (__v)

    #define FMDBRetain(__v)
    #define FMDBReturnRetained(__v) (__v)

    #define FMDBRelease(__v)

// If OS_OBJECT_USE_OBJC=1, then the dispatch objects will be treated like ObjC objects
// and will participate in ARC.
// See the section on "Dispatch Queues and Automatic Reference Counting" in "Grand Central Dispatch (GCD) Reference" for details. 
    #if OS_OBJECT_USE_OBJC
        #define FMDBDispatchQueueRelease(__v)
    #else
        #define FMDBDispatchQueueRelease(__v) (dispatch_release(__v));
    #endif
#endif

#if !__has_feature(objc_instancetype)
    #define instancetype id
#endif


typedef int(^FMDBExecuteStatementsCallbackBlock)(NSDictionary *resultsDictionary);

typedef NS_ENUM(int, FMDBCheckpointMode) {
    FMDBCheckpointModePassive  = 0, // SQLITE_CHECKPOINT_PASSIVE,
    FMDBCheckpointModeFull     = 1, // SQLITE_CHECKPOINT_FULL,
    FMDBCheckpointModeRestart  = 2, // SQLITE_CHECKPOINT_RESTART,
    FMDBCheckpointModeTruncate = 3  // SQLITE_CHECKPOINT_TRUNCATE
};

/** 对 SQLite 的封装
 *
 * FMDatabase：代表一个单独的SQLite操作实例，数据库通过它增删改查操作；
 * FMResultSet：代表查询后的结果集；
 * FMDatabaseQueue：串行队列，提供对多线程操作的支持；
 * FMDatabaseAdditions：本类用于扩展FMDatabase，用于查找表是否存在，版本号等功能；
 * FMDatabasePool：此方式官方是不推荐使用，代表是任务池，也是对多线程提供了支持。
 *
 * @note 在多线程下并发访问数据库，会引起数据竞争，此时使用 FMDatabaseQueue，而非 FMDatabase！
 *
 ### External links
 - [SQLite](http://sqlite.org/)
 - [FMDB on GitHub](https://github.com/ccgus/fmdb) including introductory documentation
 - [SQLite web site](http://sqlite.org/)
 - [FMDB mailing list](http://groups.google.com/group/fmdb)
 - [SQLite FAQ](http://www.sqlite.org/faq.html)
 */

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-interface-ivars"


@interface FMDatabase : NSObject

///-----------------
/// @name Properties
///-----------------

/** 是否应该跟踪执行
 */
@property (atomic, assign) BOOL traceExecution;

/** 是否检查退出
 */
@property (atomic, assign) BOOL checkedOut;

/** Crash on errors */
@property (atomic, assign) BOOL crashOnErrors;

/** 打印Errors
 */
@property (atomic, assign) BOOL logsErrors;

/** Dictionary of cached statements
 */
@property (atomic, retain, nullable) NSMutableDictionary *cachedStatements;

///---------------------
/// @name 实例化
///---------------------

/**实例化一个 FMDatabase
 * @param inPath SQLite数据库的路径，url 数据库文件的本地链接(不是远程URL)； 该路径可能是以下三种情况：
 *     1、文件路径：如果在磁盘里该文件不存在，则该方法内部自动创建；
 *     2、路径为 nil ：创建数据库缓存在 memory 中，关闭 FMDatabase 连接后，此数据库将被销毁。
 *     3、空字符串@"" ：在tmp目录下创建一个空数据库。关闭 FMDatabase 连接后删除此数据库；
 *
 * 例如，在 Mac OS X 系统的 tmp 文件夹中创建/打开一个数据库:
 *   FMDatabase *db = [FMDatabase databaseWithPath:@"/tmp/tmp.db"];
 * 或者，在iOS中应用程序的 Documents 目录下打开一个数据库:
 *   NSString *docsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
 *   NSString *dbPath   = [docsPath stringByAppendingPathComponent:@"test.db"];
 *   FMDatabase *db     = [FMDatabase databaseWithPath:dbPath];
 *
 * 有关临时数据库和内存数据库的更多信息，请阅读有关该主题的sqlite文档 (http://www.sqlite.org/inmemorydb.html))
 *
 * @return 创建成功，则返回 FMDatabase 对象，失败返回 nil
 */
+ (instancetype)databaseWithPath:(NSString * _Nullable)inPath;
+ (instancetype)databaseWithURL:(NSURL * _Nullable)url;
- (instancetype)initWithURL:(NSURL * _Nullable)url;
- (instancetype)initWithPath:(NSString * _Nullable)path;



///-----------------------------------
/// @name 打开和关闭数据库
///-----------------------------------

/// 数据库是否打开
@property (nonatomic) BOOL isOpen;

/** 打开数据库进行读写操作，如果数据库不存在，就创建它
 * @return 打开则返回 YES，失败返回 NO；
 *
 * @see [sqlite3_open()](http://sqlite.org/c3ref/open.html)
 * @see openWithFlags:
 * @see close
 */
- (BOOL)open;

/** 使用 flags 和一个可选的虚拟文件系统(VFS)打开一个新的数据库连接
 * @param vfsName 传递给 sqlite3_open_v2() 的vfs参数
 * @param flags 取下述三个值：
 *      SQLITE_OPEN_READONLY : 数据库只读，如果数据库不存在，则返回一个错误；
 *      SQLITE_OPEN_READWRITE 打开数据库进行读写操作，或者文件被读保护的情况下仅进行写操作。此时数据库必须存在，否则将返回一个错误。
 *      SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE 类似于 -open 方法： 打开数据库进行读写操作，如果数据库不存在就创建它。
 *
 * flags 可以选择与 SQLITE_OPEN_NOMUTEX、SQLITE_OPEN_FULLMUTEX 、SQLITE_OPEN_SHAREDCACHE 、SQLITE_OPEN_PRIVATECACHE 或 SQLITE_OPEN_URI 组合:
 *
 * @return 打开则返回 YES，失败返回 NO；
 * @see [sqlite3_open_v2()](http://sqlite.org/c3ref/open.html)
 * @see open
 * @see close
 */
- (BOOL)openWithFlags:(int)flags vfs:(NSString * _Nullable)vfsName;
- (BOOL)openWithFlags:(int)flags;


/** 关闭数据库连接
 * @return 关闭则返回 YES，失败返回 NO；
 *
 * @see [sqlite3_close()](http://sqlite.org/c3ref/close.html)
 * @see open
 * @see openWithFlags:
 */
- (BOOL)close;

/** 确认数据库是否有良好的连接
 *   1、数据库是打开的；
 *   2、如果打开，将尝试一个简单的 SELECT 语句并确认成功
 * @return 一切顺利则返回 YES；否则返回 NO
 */
@property (nonatomic, readonly) BOOL goodConnection;


///----------------------
/// @name 执行更新
///----------------------

/** 执行单个更新语句
 * @param sql 要执行的SQL语句，带有可选的'?'的占位符；
 * @param outErr 双指针 NSError，记录发生的错误；如果为 nil ，则不会返回 NSError；
 * @param ...  绑定到SQL语句中的占位符'?'的可选参数。这些可选值应该是Objective-C对象(如NSString、 NSNumber、 NSNull、 NSDate、 NSData 等)，而非基本数据类型 int 、NSInteger 等。如果可选值是其它Objective-C对象，将使用对象的 -description 方法的字符串；
 *
 * 此方法执行单个SQL update语句(即不返回结果的任何SQL，如 update、INSERT 或 DELETE )。
 * 该方法使用 sqlite3_prepare_v2()，sqlite3_bind()将值绑定到 '?' 占位符与可选的参数列表，和sqlite_step() 执行更新。
 *
 *
 * @return 成功返回 YES。如果失败，可以调用 lastError、 lastErrorCod 或 lastErrorMessage 获取失败信息；
 *
 * @note 使用 '?' 占位符将值参数绑定到该位置；这种方法比 [NSString stringWithFormat:] 手动构建 SQL 语句更安全，如果值碰巧包含需要引用的任何字符，则可能会出现问题。
 * @note 由于Swift和Objective-C变量实现之间的不兼容性，在Swift中需要使用 executeUpdate:values: 代替
 *
 * @see lastError
 * @see lastErrorCode
 * @see lastErrorMessage
 * @see [`sqlite3_bind`](http://sqlite.org/c3ref/bind_blob.html)
 */
- (BOOL)executeUpdate:(NSString*)sql withErrorAndBindings:(NSError * _Nullable __autoreleasing *)outErr, ...;
- (BOOL)executeUpdate:(NSString*)sql, ...;

- (BOOL)update:(NSString*)sql withErrorAndBindings:(NSError * _Nullable __autoreleasing *)outErr, ...  __deprecated_msg("Use executeUpdate:withErrorAndBindings: instead");;


/** 执行单个更新语句
 * @param format 要执行的SQL，带有'%@'、'%d'等样式的转义序列；
 * @param ... 绑定到SQL语句中的可选参数，与 '%s'、'%d'成对使用。
 *
 * 此方法执行单个SQL update语句(即不返回结果的任何SQL，如 update、INSERT 或 DELETE )。
 * 该方法使用 sqlite3_prepare_v2() 和 sqlite_step() 来执行更新。不同于 -executeUpdate 方法使用'?'占位符， 它使用'%s'、'%d'等来构建SQL语句。
 *
 * @return 成功返回 YES。如果失败，可以调用 lastError、 lastErrorCod 或 lastErrorMessage 获取失败信息；
 *
 * @note [db executeUpdateWithFormat:@"INSERT INTO test (name) VALUES (%@)", @"Gus"];
 * @note [db executeUpdate:@"INSERT INTO test (name) VALUES (?)", @"Gus"];
 *
 * @note '%@'、'%d'等样式的转义序列只允许使用在SQLite 语句 占位符`?` 的地方。不能用于表名、列名或任何其他非值上下文；此方法也不能与 pragma 语句之类的语句一起使用。
 */

- (BOOL)executeUpdateWithFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);


/** 执行单个更新语句
 * @param sql 要执行的SQL语句，带有可选的'?'的占位符；
 * @param values 数组的元素将对应绑定到 SQL语句占位符'?' 处；
 * @param error 双指针 NSError，记录发生的错误；如果为 nil ，则不会返回 NSError；
 * 此方法执行单个SQL update语句(即不返回结果的任何SQL，如 update、INSERT 或 DELETE )。
 * 该方法使用sqlite3_prepare_v2()和sqlite3_bind()绑定'?'占位符，带有可选的参数列表。
 *
 * @return 成功返回 YES。如果失败，可以调用 lastError、 lastErrorCod 或 lastErrorMessage 获取失败信息；
 */

- (BOOL)executeUpdate:(NSString*)sql values:(NSArray * _Nullable)values error:(NSError * _Nullable __autoreleasing *)error;
- (BOOL)executeUpdate:(NSString*)sql withArgumentsInArray:(NSArray *)arguments;

/** 执行单个更新语句
 * @param sql 要执行的SQL语句，带有可选的'?'的占位符；
 * @param arguments NSDictionary的kay-value 将绑定到 SQL语句占位符'?' 处；
 *
 * 此方法执行单个SQL update语句(即不返回结果的任何SQL，如 update、INSERT 或 DELETE)。
 * 该方法使用 sqlite3_prepare_v2() 和 sqlite_step() 来执行更新。不同于 -executeUpdate 方法使用'?'占位符， 它使用'%s'、'%d'等来构建SQL语句。
 *
 * @return 成功返回 YES。如果失败，可以调用 lastError、 lastErrorCod 或 lastErrorMessage 获取失败信息；
 */
- (BOOL)executeUpdate:(NSString*)sql withParameterDictionary:(NSDictionary *)arguments;
- (BOOL)executeUpdate:(NSString*)sql withVAList: (va_list)args;

/** 使用 Block 执行多个SQL语句更新
 * @param  sql  要执行的SQL语句
 * @param block 带有返回值的Block，成功返回0；失败时将停止SQL的批量执行；可以为 nil
 * 执行多个组合在一起的SQL语句，如 .dump 指令。不接受参数，而是简单地期望一个包含多个SQL语句的字符串，每个SQL语句以分号结束。
 * @return 成功返回 YES。如果失败，可以调用 lastError、 lastErrorCod 或 lastErrorMessage 获取失败信息；
 *
 * @see [sqlite3_exec()](http://sqlite.org/c3ref/exec.html)
 */
- (BOOL)executeStatements:(NSString *)sql withResultBlock:(__attribute__((noescape)) FMDBExecuteStatementsCallbackBlock _Nullable)block;
- (BOOL)executeStatements:(NSString *)sql;


/** 最后插入的一行的rowid
 * @note rowid 是SQLite表中每个条目都有一个唯一的64位带符号整数键；如果表的列的类型是‘INTEGER PRIMARY KEY’，那么该列就是rowid的另一个别名。
 * @note 如果数据库连接上从未发生过成功的 INSERT，则返回0。
 * @see [sqlite3_last_insert_rowid()](http://sqlite.org/c3ref/last_insert_rowid.html)
 */
@property (nonatomic, readonly) int64_t lastInsertRowId;

/** 由先前的SQL语句更改的行数
 * @note 只计算由INSERT、UPDATE或DELETE语句直接指定的更改的数据库行数
 * @see [sqlite3_changes()](http://sqlite.org/c3ref/changes.html)
 */

@property (nonatomic, readonly) int changes;


///-------------------------
/// @name 检索结果
///-------------------------

/** 执行查询
 * @param sql 查询语句，带有可选的'?'的占位符；
 * @param ... 绑定到SQL语句中的可选参数，与 '%s'、'%d'成对使用。
 * @return 查询成功返回 FMResultSet 对象；失败则返回 nil；可以设置双指针 NSError ，也可以调用 lastError、 lastErrorCod 或 lastErrorMessage 获取失败信息；
 * 为了遍历查询结果，可以使用 while([FMResultSet next]) 循环从一条记录到另一条记录。
 * 此方法对任何可选值参数使用sqlite3_bind()，这可以正确地转义需要转义序列的任何字符(例如引号)，从而消除简单的SQL错误，并防止SQL注入攻击。
 
 * @see [`sqlite3_bind`](http://sqlite.org/c3ref/bind_blob.html)
 */
- (FMResultSet * _Nullable)executeQuery:(NSString*)sql, ...;

/** 执行查询
 * @param format 要执行查询的SQL，带有'%@'、'%d'等样式的转义序列；
 * @param ... 绑定到SQL语句中的可选参数，与 '%@'、'%d'成对使用。
 * @return 查询成功返回 FMResultSet 对象；失败则返回 nil；可以设置双指针 NSError ，也可以调用 lastError、 lastErrorCod 或 lastErrorMessage 获取失败信息；
 *
 * @note [db executeQueryWithFormat:@"SELECT * FROM test WHERE name=%@", @"Gus"];
 * @note [db executeQuery:@"SELECT * FROM test WHERE name=?", @"Gus"];
 * @note '%@'、'%d'等样式的转义序列只允许使用在SQLite 语句 占位符`?` 的地方。不能用于表名、列名或任何其他非值上下文；此方法也不能与 pragma 语句之类的语句一起使用。
 */
- (FMResultSet * _Nullable)executeQueryWithFormat:(NSString*)format, ... NS_FORMAT_FUNCTION(1,2);

/** 执行查询
 * @param sql 查询语句，带有可选的'?'的占位符；
 * @param values 数组的元素将对应绑定到 SQL语句占位符'?' 处；
 * @param error 双指针 NSError，记录发生的错误；如果为 nil ，则不会返回 NSError；
 * @return 查询成功返回 FMResultSet 对象；失败则返回 nil；可以设置双指针 NSError ，也可以调用 lastError、 lastErrorCod 或 lastErrorMessage 获取失败信息；
*/
- (FMResultSet * _Nullable)executeQuery:(NSString *)sql values:(NSArray * _Nullable)values error:(NSError * _Nullable __autoreleasing *)error;
- (FMResultSet * _Nullable)executeQuery:(NSString *)sql withArgumentsInArray:(NSArray *)arguments;


/** 执行查询
 * @param sql 查询语句，带有可选的'?'的占位符；
 * @param arguments NSDictionary的kay-value 将绑定到 SQL语句占位符'?' 处；
 *
 * @return 查询成功返回 FMResultSet 对象；失败则返回 nil；可以设置双指针 NSError ，也可以调用 lastError、 lastErrorCod 或 lastErrorMessage 获取失败信息；
 */
- (FMResultSet * _Nullable)executeQuery:(NSString *)sql withParameterDictionary:(NSDictionary * _Nullable)arguments;
- (FMResultSet * _Nullable)executeQuery:(NSString *)sql withVAList:(va_list)args;

///-------------------
/// @name 事务
///-------------------

/** 事务: 主要用于处理操作量大，复杂度高的数据。
 *      比如说，在人员管理系统中，你删除一个人员，你既需要删除人员的基本资料，也要删除和该人员相关的信息，如信箱，文章等等，这样， 这些数据库操作语句就构成一个事务！
 *
 * 一般来说，事务是必须满足4个条件（ACID）：
 *    原子性 Atomicity，或称不可分割性 ：一个事务中的所有操作，要么全部完成，要么全部不完成，不会结束在中间某个环节。
 *                事务在执行过程中发生错误，会被回滚（Rollback）到事务开始前的状态，就像这个事务从来没有执行过一样。
 *     一致性 Consistency ：在事务开始之前和事务结束以后，数据库的完整性没有被破坏。
 *               这表示写入的资料必须完全符合所有的预设规则，这包含资料的精确度、串联性以及后续数据库可以自发性地完成预定的工作。
 *   隔离性 Isolation，又称独立性：数据库允许多个并发事务同时对其数据进行读写和修改的能力，
 *                          隔离性可以防止多个事务并发执行时由于交叉执行而导致数据的不一致。
 *        事务隔离分为不同级别，包括读未提交 Read uncommitted、读提交read committed、可重复读repeatable read和串行化Serializable
 *   持久性Durability ：事务处理结束后，对数据的修改就是永久的，即便系统故障也不会丢失。
 */


/** 开启事务
 * @return 成功返回 YES。如果失败，可以调用 lastError、 lastErrorCod 或 lastErrorMessage 获取失败信息；
 *
 * @warning 与 SQLite 的 BEGIN TRANSACTION 不同，此方法当前执行的是互斥事务，而不是延迟事务；
 *       在FMDB的未来版本中，这种行为可能会改变，因此该方法最终可能采用标准SQLite行为并执行延迟事务。
 *       建议使用 -beginExclusiveTransaction ，保证代码在未来不会被修改。
 */
- (BOOL)beginTransaction;

/** 开始一个延迟的事务
 * @return 成功返回 YES。如果失败，可以调用 lastError、 lastErrorCod 或 lastErrorMessage 获取失败信息；
 */
- (BOOL)beginDeferredTransaction;

/** 立即开启事务
 * @return 成功返回 YES。如果失败，可以调用 lastError、 lastErrorCod 或 lastErrorMessage 获取失败信息；
 */
- (BOOL)beginImmediateTransaction;

/** 开始互斥事务
 * @return 成功返回 YES。如果失败，可以调用 lastError、 lastErrorCod 或 lastErrorMessage 获取失败信息；
 */
- (BOOL)beginExclusiveTransaction;

/** 提交一个事务
 * 提交一个由 -beginTransaction 或 -beginDeferredTransaction 启动的事务。
 * @return 成功返回 YES。如果失败，可以调用 lastError、 lastErrorCod 或 lastErrorMessage 获取失败信息；
 */
- (BOOL)commit;

/** 回滚事务
 * 回滚用 -beginTransaction 或 -beginDeferredTransaction 启动的事务。
 * @return 成功返回 YES。如果失败，可以调用 lastError、 lastErrorCod 或 lastErrorMessage 获取失败信息；
 */
- (BOOL)rollback;

/** 确定当前是否处于事务中
 */
@property (nonatomic, readonly) BOOL isInTransaction;
- (BOOL)inTransaction __deprecated_msg("Use isInTransaction property instead");


///----------------------------------------
/// @name 缓存语句和结果集
///----------------------------------------

/** 清除缓存
 */
- (void)clearCachedStatements;

/** 关闭所有打开的结果集
 */
- (void)closeOpenResultSets;

/** 数据库是否有任何打开的结果集
 */
@property (nonatomic, readonly) BOOL hasOpenResultSets;

/** 是否应该缓存 statements
 */
@property (nonatomic) BOOL shouldCacheStatements;

/** 中断数据库操作
 * 将导致任何挂起的数据库操作中止并在其最早的时机返回
 * @return 成功返回 YES。如果失败，可以调用 lastError、 lastErrorCod 或 lastErrorMessage 获取失败信息；
 */
- (BOOL)interrupt;

///-------------------------
/// @name 加密方法
/// @warning 需要购买 sqlite 加密扩展才能使用此方法
/// @see https://www.zetetic.net/sqlcipher/
///-------------------------

/** 设置加密密钥
 */
- (BOOL)setKey:(NSString*)key;

/** 重置加密密钥
 */
- (BOOL)rekey:(NSString*)key;

/** 使用 keyData 设置加密密钥
 */
- (BOOL)setKeyWithData:(NSData *)keyData;

/** 使用 keyData 重置加密密钥。
 */
- (BOOL)rekeyWithData:(NSData *)keyData;


///------------------------------
/// @name 一般方法
///------------------------------

/** 数据库路径
 */
@property (nonatomic, readonly, nullable) NSString *databasePath;
@property (nonatomic, readonly, nullable) NSURL *databaseURL;

/** The underlying SQLite handle
 */
@property (nonatomic, readonly) void *sqliteHandle;


///-----------------------------
/// @name 获取错误信息
///-----------------------------

/** 获取最后一个操作的错误信息
 * @note 如果前面操作失败，但最后一个操作成功，该值未定义
 * @see [sqlite3_errmsg()](http://sqlite.org/c3ref/errcode.html)
 */
- (NSString*)lastErrorMessage;

/** 获取最后一个操作的错误码
 * @note 如果前面操作失败，但最后一个操作成功，该值未定义
 * @see [sqlite3_errcode()](http://sqlite.org/c3ref/errcode.html)
 */
- (int)lastErrorCode;

/** 获取最后一个操作的扩展错误码
 * @note 如果前面操作失败，但最后一个操作成功，该值未定义
 
 @see [sqlite3_errcode()](http://sqlite.org/c3ref/errcode.html)
 @see [2. Primary Result Codes versus Extended Result Codes](http://sqlite.org/rescode.html#primary_result_codes_versus_extended_result_codes)
 @see [5. Extended Result Code List](http://sqlite.org/rescode.html#extrc)
 */
- (int)lastExtendedErrorCode;

/** 判断 lastError 、-lastErrorCode、 -lastErrorMessage 是否有错误
 */
- (BOOL)hadError;

/** 获取最后一个操作的错误
 */
- (NSError *)lastError;

@property (nonatomic) NSTimeInterval maxBusyRetryTimeInterval;


///------------------
/// @name FMDB 使用 SQLite 事务 Save Point
///
/// 在SQLite中，事务提供了批量处理，批量撤销的功能。当批量操作中有一步无法完成操作，就会把执行过的语句都撤销，恢复到撤销前的状态。
/// 但是由于 SQLite 不支持事务嵌套，所以用户不能直接完成复杂的事务；不过，SQLite提供了保存点Save Point机制。
/// 用户可以在事务中添加保存点，然后根据情况，回滚到指定的保存点，并可以重新执行保存点之后的代码。
/// 这样，通过保存点机制，可以变相实现事务嵌套。
///------------------

/** 创建保存点
 * @param name 保存点的名称
 * @param outErr 双指针 NSError，记录发生的错误；如果为 nil ，则不会返回 NSError；
 * @return 成功返回 YES。如果失败，可以调用 -lastError、 -lastErrorCod 或 -lastErrorMessage 获取失败信息；
 */
- (BOOL)startSavePointWithName:(NSString*)name error:(NSError * _Nullable __autoreleasing *)outErr;

/** 撤销保存点
 */
- (BOOL)releaseSavePointWithName:(NSString*)name error:(NSError * _Nullable __autoreleasing *)outErr;

/** 回滚到保存点
 */
- (BOOL)rollbackToSavePointWithName:(NSString*)name error:(NSError * _Nullable __autoreleasing *)outErr;

/** 执行保存点后的代码
 * @param block 要在保存点内执行的代码块
 * @return 错误对应的NSError；如果没有错误返回nil
 */
- (NSError * _Nullable)inSavePoint:(__attribute__((noescape)) void (^)(BOOL *rollback))block;


///-----------------
/// @name Checkpoint
/// 检查点只是一个数据库事件，它存在的根本意义在于减少崩溃恢复 Crash Recovery 时间
/// 当修改数据时，需要首先将数据读入内存中 Buffer Cache，修改数据的同时，Oracle会记录重做信息（Redo）用于恢复。
/// 因为有了重做信息的存在，Oracle 不需要在提交时立即将变化的数据写回磁盘（立即写的效率会很低），
/// 重做（Redo）的存在也正是为了在数据库崩溃之后，数据就可以恢复。
///
/// 最常见的情况，数据库可以因为断电而Crash，那么内存中修改过的、尚未写入文件的数据将会丢失。
/// 在下一次数据库启动之后，Oracle可以通过重做日志（Redo）进行事务重演，也就是进行前滚，将数据库恢复到崩溃之前的状态，
/// 然后数据库可以打开提供使用，之后Oracle可以将未提交的数据进行回滚。
///
/// 在这个过程中，通常大家最关心的是数据库要经历多久才能打开。也就是需要读取多少重做日志才能完成前滚。
/// 当然用户希望这个时间越短越好，Oracle也正是通过各种手段在不断优化这个过程，缩短恢复时间。
///
/// 检查点的存在就是为了缩短这个恢复时间。
///
/// 当检查点发生时，Oracle会通知 DBWR 进程，把修改过的数据，也就是Checkpoint SCN之前的脏数据从Buffer Cache写入磁盘，
/// 当写入完成之后，CKPT进程更新控制文件和数据文件头，记录检查点信息，标识变更。
///-----------------

// https://www.cnblogs.com/huahuahu/p/sqlite-zhiWAL-mo-shi.html
/** Sqlite 之 WAL 模式 : Write-Ahead Log 模式是另一种实现事务原子性的方法
 *  优点：
 *      在大多数情况下更快；
 *      并行性更高。因为读操作和写操作可以并行
 *      文件IO更加有序化，串行化（more sequential）
 *      使用fsync()的次数更少，在fsync()调用时好时坏的机器上较为未定。
 *  缺点：
 *      一般情况下需要VFS支持共享内存模式。(shared-memory primitives)
 *      操作数据库文件的进程必须在同一台主机上，不能用在网络操作系统。
 *      持有多个数据库文件的数据库连接对于单个数据库时原子的，对于全部数据库是不原子的。
 *      进入WAL模式以后不能修改page的size。
 *      不能打开只读的WAL数据库(Read-Only Databases)，这进程必须有"-shm"文件的写权限。
 *      对于只进行读操作，很少进行写操作的数据库，要慢那么1到2个百分点。
 *      会有多余的"-wal"和"-shm"文件
 *      需要开发者注意 checkpointing
 *
 * 原理：
 *      回滚日志的方法是把为改变的数据库文件内容写入日志里，然后把改变后的内容直接写到数据库文件中去。
 *      在系统crash或掉电的情况下，日志里的内容被重新写入数据库文件中。
 *      日志文件被删除，标志commit着一次commit的结束。
 *
 *      WAL 模式于此此相反。原始为改变的数据库内容在数据库文件中，对数据库文件的修改被追加到单独的WAL文件中。
 *      当一条记录被追加到WAL文件后，标志着一次commit的结束。
 *      因此一次commit不必对数据库文件进行操作，当正在进行写操作时，可以同时进行读操作。
 *      多个事务的内容可以追加到一个WAL文件的末尾。
 *
 *
 */

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


///----------------------------
/// @name SQLite库状态
///----------------------------

/** 该库是否是线程安全的
 *
 * @return NO 当且仅当SQLite编译时，由于编译时特性SQLITE_THREADSAFE被设置为0，使用互斥代码省略
 * @see [sqlite3_threadsafe()](http://sqlite.org/c3ref/threadsafe.html)
 */

+ (BOOL)isSQLiteThreadSafe;

/** Run-time library version numbers
 
 @return The sqlite library version string.
 
 @see [sqlite3_libversion()](http://sqlite.org/c3ref/libversion.html)
 */
+ (NSString*)sqliteLibVersion;
+ (NSString*)FMDBUserVersion;
+ (SInt32)FMDBVersion;


///------------------------
/// @name SQL函数
///------------------------

/** Adds SQL functions or aggregates or to redefine the behavior of existing SQL functions or aggregates.
 
 For example:
 
    [db makeFunctionNamed:@"RemoveDiacritics" arguments:1 block:^(void *context, int argc, void **argv) {
        SqliteValueType type = [self.db valueType:argv[0]];
        if (type == SqliteValueTypeNull) {
            [self.db resultNullInContext:context];
             return;
        }
        if (type != SqliteValueTypeText) {
            [self.db resultError:@"Expected text" context:context];
            return;
        }
        NSString *string = [self.db valueString:argv[0]];
        NSString *result = [string stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:nil];
        [self.db resultString:result context:context];
    }];

    FMResultSet *rs = [db executeQuery:@"SELECT * FROM employees WHERE RemoveDiacritics(first_name) LIKE 'jose'"];
    NSAssert(rs, @"Error %@", [db lastErrorMessage]);
 
 @param name Name of function.

 @param arguments Maximum number of parameters.

 @param block The block of code for the function.

 @see [sqlite3_create_function()](http://sqlite.org/c3ref/create_function.html)
 */

- (void)makeFunctionNamed:(NSString *)name arguments:(int)arguments block:(void (^)(void *context, int argc, void * _Nonnull * _Nonnull argv))block;

- (void)makeFunctionNamed:(NSString *)name maximumArguments:(int)count withBlock:(void (^)(void *context, int argc, void * _Nonnull * _Nonnull argv))block __deprecated_msg("Use makeFunctionNamed:arguments:block:");

typedef NS_ENUM(int, SqliteValueType) {
    SqliteValueTypeInteger = 1,
    SqliteValueTypeFloat   = 2,
    SqliteValueTypeText    = 3,
    SqliteValueTypeBlob    = 4,
    SqliteValueTypeNull    = 5
};

- (SqliteValueType)valueType:(void *)argv;

/** 获取自定义函数中指定参数的值
 * @param value 指定的参数
 * @return 指定参数的值
 */
- (int)valueInt:(void *)value;
- (long long)valueLong:(void *)value;
- (double)valueDouble:(void *)value;
- (NSData * _Nullable)valueData:(void *)value;
- (NSString * _Nullable)valueString:(void *)value;

/** 从自定义函数返回空值
 * @param context 将返回空值的上下文
 */
- (void)resultNullInContext:(void *)context NS_SWIFT_NAME(resultNull(context:));

/** 自定义函数的返回值
 * @param value 返回值
 * @param context 需要返回值的上下文
 */
- (void)resultInt:(int) value context:(void *)context;
- (void)resultLong:(long long)value context:(void *)context;
- (void)resultDouble:(double)value context:(void *)context;
- (void)resultData:(NSData *)data context:(void *)context;
- (void)resultString:(NSString *)value context:(void *)context;
- (void)resultError:(NSString *)error context:(void *)context;
- (void)resultErrorCode:(int)errorCode context:(void *)context;

/** 记录自定义函数中的内存错误
 * @param context 返回错误的上下文
 */
- (void)resultErrorNoMemoryInContext:(void *)context NS_SWIFT_NAME(resultErrorNoMemory(context:));

/** 记录 字符串或BLOB太长无法在自定义函数中表示 的错误
 * @param context 返回错误的上下文
 */
- (void)resultErrorTooBigInContext:(void *)context NS_SWIFT_NAME(resultErrorTooBig(context:));

///---------------------
/// @name 日期格式化
///---------------------

/** 生成一个不会被时区或地区的影响的 NSDateFormatter
 *  @param format 一个有效的 NSDateFormatter 格式字符串
 * 使用此方法生成 NSDateFormatter 以设置 dateFormat 属性；如：
 * myDB.dateFormat = [FMDatabase storeableDateFormat:@"yyyy-MM-dd HH:mm:ss"];
 *
 * @warning 此处的 NSDateFormatter 不是线程安全的，应该只分配给一个 FMDB 实例，不应该用于其他目的。
 */
+ (NSDateFormatter *)storeableDateFormat:(NSString *)format;

/** 测试数据库是否分配了 NSDateFormatter
 */
- (BOOL)hasDateFormatter;

/** 将 NSDateFormatter 设置为使用 sqlite的字符串日期，而不是使用默认的UNIX时间戳。
 * @param format 默认为nil，使用UNIX时间戳。
 * @warning NSDateFormatter 没有 -getter 方法，而且 NSDateFormatter 不是线程安全的。
 */
- (void)setDateFormat:(NSDateFormatter * _Nullable)format;

/** 使用当前数据库的 NSDateFormatter 将提供的NSString转换为 NSDate
 * @return 如果没有设置 NSDateFormatter ，则返回 nil
 */
- (NSDate * _Nullable)dateFromString:(NSString *)s;

/**使用当前数据库的 NSDateFormatter 将提供的 NSDate 转换为 NSString
 * @return 如果没有设置 NSDateFormatter ，则返回 nil
 */
- (NSString * _Nullable)stringFromDate:(NSDate *)date;

@end


/** Objective-C wrapper for `sqlite3_stmt`
 * 对 sqlite3_stmt 的封装。通常在使用FMDB时，不需要直接与' FMStatement '进行交互，而只需与 FMDatabase 和 FMResultSet 进行交互。
 */
@interface FMStatement : NSObject {
    void *_statement;
    NSString *_query;
    long _useCount;
    BOOL _inUse;
}

///-----------------
/// @name Properties
///-----------------

/** Usage count */

@property (atomic, assign) long useCount;

/** SQL statement */

@property (atomic, retain) NSString *query;

/** SQLite sqlite3_stmt
 
 @see [`sqlite3_stmt`](http://www.sqlite.org/c3ref/stmt.html)
 */

@property (atomic, assign) void *statement;

/** Indication of whether the statement is in use */

@property (atomic, assign) BOOL inUse;

///----------------------------
/// @name Closing and Resetting
///----------------------------

/** Close statement */

- (void)close;

/** Reset statement */

- (void)reset;

@end

#pragma clang diagnostic pop

NS_ASSUME_NONNULL_END
