# Persistence
数据存储
* 前篇：[Sqlite 的简单了解](https://www.jianshu.com/p/a1c395cc6e20)

[FMDB](https://github.com/ccgus/fmdb) 对 [SQLite3](https://www.sqlite.org/index.html) 的C函数做了面向对象的封装：针对数据库提供了增删查改等接口，以及事务处理 等，并通过一个GCD的串行队列保证在多线程环境下的数据安全。
这些功能主要封装在以下几个类中：
* `FMStatement` ：是对 SQLite 的预处理语句 `sqlite3_stmt` 的封装，并增加了缓存该语句的功能；
* `FMDatabase`：代表一个单独的SQLite操作实例，打开或者关闭数据库，对数据库执行增、删、改、查等操作，以及以事务方式处理数据等；
* `FMResultSet`：封装了查询后的结果集，通过 `-next` 获取查询的数据；
* `FMDatabaseQueue`：将对数据库的所有操作，都封装在串行队列执行！避免数据竞态问题，保证多线程环境下的数据安全；
* `FMDatabaseAdditions`：是`FMDatabase`的分类，扩展了查找表是否存在，版本号，表信息等功能；
* `FMDatabasePool`：`FMDatabase`的对象池封装，在多线程环境中访问单个`FMDatabase`对象容易引起问题，可以通过`FMDatabasePool`对象池来解决多线程下的访问安全问题；不推荐使用，优先使用`FMDatabaseQueue`。

#### 1、`FMStatement`

######  `Cached Statement `功能 

我们执行的 Sql 语句，需要通过 `sqlite3_prepare_v2()` 函数编译为 _预处理语句_ `sqlite3_stmt`，然后再由 `sqlite3_step()` 函数执行该语句！这些过程明显都是耗时操作，如果执行的 SQL 语句大量重复，为提升操作效率，FMDB 提供了缓存这些 `sqlite3_stmt` 语句的功能！
`FMDatabase` 的 `shouldCacheStatements` 属性用来管理是否缓存这些语句， `cachedStatements` 字典用来缓存这些语句！而 `FMStatement` 通过对 `sqlite3_stmt` 的封装，作为一个元素被存储在字典 `cachedStatements` 中！

##### 1.1、`sqlite3_stmt` 的状态记录

```
/** 从缓存中取出 sqlite3_stmt ，并重复使用的次数 */
@property (atomic, assign) long useCount;

/** 需要执行的 SQL 语句 */
@property (atomic, retain) NSString *query;

/** 预处理语句 sqlite3_stmt ：将 Sql 通过 sqlite3_prepare_v2() 函数编译而来 */
@property (atomic, assign) void *statement;

/** 是否正在使用该条语句 */
@property (atomic, assign) BOOL inUse;
```

##### 1.2、释放`sqlite3_stmt`

`sqlite3_stmt` 作为 C 变量，需要调用它的析构函数 `sqlite3_finalize()`释放内存，否则会造成内存泄漏！

```
/** 释放 sqlite3_stmt 内存 */
- (void)close {
    if (_statement) {
        sqlite3_finalize(_statement);
        _statement = 0x00;
    }
    _inUse = NO;
}
```

##### 1.3、重置`sqlite3_stmt`

`sqlite3_stmt` 是可以被 `sqlite3_step()` 函数多次调用的，每调用一次，它就会向下执行一次：
* 对于使用 `SELECT` 命令筛选数据时，可以使用 `while()` 循环多次调用，获取结果集中的一条条数据；
* 对于 `CREATE 、DROP 、INSERT 、DELETE、UPDATE` 等 Sqlite 命令，只需执行一次，再次执行是没有意义的，`sqlite3_step()` 函数会返回 `SQLITE_ROW` 表明该  `sqlite3_stmt` 已经被执行过一次！

因此，针对缓存的 `sqlite3_stmt`，从缓存中取出之后，需要先重置该语句；以免被缓存前的其它操作所影响。

```
/** 重置  */
- (void)reset {
    if (_statement) {
        sqlite3_reset(_statement);
    }
    _inUse = NO;
}
```



#### 2、`FMDatabase`

`FMDatabase`代表一个单独的SQLite操作实例，打开或者关闭数据库，对数据库执行增、删、改、查等操作，以及以事务方式处理数据等!


##### 2.1、实例化一个 `FMDatabase`


```
+ (instancetype)databaseWithPath:(NSString * _Nullable)inPath;
+ (instancetype)databaseWithURL:(NSURL * _Nullable)url;
- (instancetype)initWithURL:(NSURL * _Nullable)url;
- (instancetype)initWithPath:(NSString * _Nullable)path{
    assert(sqlite3_threadsafe()); 
    self = [super init];
    if (self) {
        _databasePath               = [path copy];
        _openResultSets             = [[NSMutableSet alloc] init];
        _db                         = nil;//数据库为空
        _logsErrors                 = YES;
        _crashOnErrors              = NO;
        _maxBusyRetryTimeInterval   = 2;//默认为2
        _isOpen                     = NO;//默认数据库关闭
    }
    return self;
}
```

创建 `FMDatabase` 实例时数据库并没有被创建，只是给了数据库一个名字！`-open` 方法调用 `sqlite3_open()` 函数才真正获取到数据库!
 
针对该数据库的路径，可能出现以下情况：
* 1、文件路径：如果在磁盘里该文件不存在，则该方法内部自动创建；
* 2、路径为 `nil` ：创建数据库缓存在 memory 中，关闭 `FMDatabase` 连接后，此数据库将被销毁。
* 3、空字符串`@“”` ：在tmp目录下创建一个空数据库。关闭 `FMDatabase` 连接后删除此数据库；


##### 2.2、打开和关闭数据库

```
/// 数据库是否打开
@property (nonatomic) BOOL isOpen;

/** 打开数据库  */
- (BOOL)openWithFlags:(int)flags vfs:(NSString * _Nullable)vfsName;
- (BOOL)openWithFlags:(int)flags;
- (BOOL)open{
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

/** 中断数据库操作 */
- (BOOL)interrupt{
    if (_db) {
        sqlite3_interrupt([self sqliteHandle]);
        return YES;
    }
    return NO;
}

/** 确认数据库是否有良好的连接：
 *   1、数据库是打开的；
 *   2、如果打开，将尝试一个简单的 SELECT 语句并确认成功
 * @return 一切顺利则返回 YES；否则返回 NO
 */
@property (nonatomic, readonly) BOOL goodConnection;
```

数据库的打开与关闭，都是耗时操作！因此需要创建一个单例类打开数据库，所有的操作就封装该类的方法中！


##### 2.3、缓存与结果集

###### 2.3.1、缓存

```
/** 是否应该缓存 statements
 * 针对大量重复的 Sql 语句，通过缓存，可以提升程序的性能；但也要注意它对内存的消耗也是非常大的。
 */
@property (nonatomic) BOOL shouldCacheStatements;

/** 缓存 FMStatement 的字典  */
@property (atomic, retain, nullable) NSMutableDictionary *cachedStatements;

/** 清除缓存语句 */
- (void)clearCachedStatements;
```


###### 配置缓存

```
/** 重写 shouldCacheStatements 的 -set 方法
 * 根据情况为字典 cachedStatements 赋值
 */
- (void)setShouldCacheStatements:(BOOL)value {
    _shouldCacheStatements = value;
    if (_shouldCacheStatements && !_cachedStatements) {
        [self setCachedStatements:[NSMutableDictionary dictionary]];
    }
    if (!_shouldCacheStatements) {
        [self setCachedStatements:nil];//清空缓存数据
    }
}
```

###### 查询与设置缓存

```
/** 查询缓存语句 */
- (FMStatement*)cachedStatementForQuery:(NSString*)query {
    NSMutableSet* statements = [_cachedStatements objectForKey:query];
    return [[statements objectsPassingTest:^BOOL(FMStatement* statement, BOOL *stop) {
        *stop = ![statement inUse];
        return *stop;
    }] anyObject];
}

/** 设置缓存语句 */
- (void)setCachedStatement:(FMStatement*)statement forQuery:(NSString*)query {
    NSParameterAssert(query);
    if (!query) {
        NSLog(@"API misuse, -[FMDatabase setCachedStatement:forQuery:] query must not be nil");
        return;
    }
    query = [query copy];
    [statement setQuery:query];
    NSMutableSet* statements = [_cachedStatements objectForKey:query];
    if (!statements) {
        statements = [NSMutableSet set];
    }
    [statements addObject:statement];
    [_cachedStatements setObject:statements forKey:query];
    FMDBRelease(query);
}
```

###### 清除缓存

```
/** 清除缓存语句 */
- (void)clearCachedStatements {
    /** 1、首先遍历字典，将 FMStatement 持有的 sqlite3_stmt 全部释放 */
    for (NSMutableSet *statements in [_cachedStatements objectEnumerator]) {
        for (FMStatement *statement in [statements allObjects]) {
            [statement close];//释放 sqlite3_stmt
        }
    }
    /** 2、其次将字典中的元素全部移除 */
    [_cachedStatements removeAllObjects];
}
```

###### 2.3.2、结果集

对于 `-executeQuery` 方法查询数据得到的结果集 `FMResultSet`，`FMDatabase` 总会将其存储在数组 `_openResultSets` 上！当然，`FMDatabase` 也提供了删除这些数据的方法：

```
/** 关闭结所有打开的结果集 ***/
- (void)closeOpenResultSets {
    NSSet *openSetCopy = FMDBReturnAutoreleased([_openResultSets copy]);
    for (NSValue *rsInWrappedInATastyValueMeal in openSetCopy) {
        FMResultSet *rs = (FMResultSet *)[rsInWrappedInATastyValueMeal pointerValue];
        [rs setParentDB:nil];
        [rs close];
        [_openResultSets removeObject:rsInWrappedInATastyValueMeal];
    }
}

/** 是否有打开的结果集 ***/
- (BOOL)hasOpenResultSets {
    return [_openResultSets count] > 0;
}
```

但是，假如 `FMResultSet` 实例调用  `-close `  关闭该结果集，那么又如何同步删除数组 `_openResultSets` 上的元素呢？

```
@implementation FMResultSet

- (void)close {
    [_statement reset];
    FMDBRelease(_statement);
    _statement = nil;
    /** FMResultSet 关闭时，需要FMDatabase从 _openResultSets 移除该结果集 */
    [_parentDB resultSetDidClose:self];
    [self setParentDB:nil];
}
@end
```

可以看到 `FMResultSet` 的  `-close ` 方法中调用了`FMDatabase` 的 `-resultSetDidClose` 方法：

```
/** FMResultSet 关闭时，需要FMDatabase从 _openResultSets 移除该结果集 */
- (void)resultSetDidClose:(FMResultSet *)resultSet {
    NSValue *setValue = [NSValue valueWithNonretainedObject:resultSet];
    [_openResultSets removeObject:setValue];
}
```

如此，就做到了数据同步！

##### 2.4、执行更新

###### 2.4.1、`-executeUpdate` 系列
FMDB 的 `-executeUpdate` 系列方法可以执行 `CREATE` 、`DROP` 、`INSERT` 、`DELETE`、`UPDATE` 等 Sqlite 语句！


```
/** 执行单个更新语句 
 * 如果语句执行失败，可以通过双指针 `NSError`获取错误原因；也可以调用 `-lastError`、 `-lastErrorCod` 或 `-lastErrorMessage` 获取失败信息。
 */
- (BOOL)executeUpdate:(NSString*)sql withErrorAndBindings:(NSError * _Nullable __autoreleasing *)outErr, ...;
- (BOOL)executeUpdate:(NSString*)sql, ...;
- (BOOL)update:(NSString*)sql withErrorAndBindings:(NSError * _Nullable __autoreleasing *)outErr, ...  __deprecated_msg("Use executeUpdate:withErrorAndBindings: instead");;
- (BOOL)executeUpdate:(NSString*)sql values:(NSArray * _Nullable)values error:(NSError * _Nullable __autoreleasing *)error;
- (BOOL)executeUpdate:(NSString*)sql withArgumentsInArray:(NSArray *)arguments;
- (BOOL)executeUpdate:(NSString*)sql withParameterDictionary:(NSDictionary *)arguments;
- (BOOL)executeUpdate:(NSString*)sql withVAList: (va_list)args;
- (BOOL)executeUpdateWithFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
```


上述方法，其实质都是执行 `-executeUpdate:error:withArgumentsInArray:orDictionary:orVAList:` 

```
//数据库是否存在：打开即存在
- (BOOL)databaseExists {
    return _isOpen;
}

- (BOOL)executeUpdate:(NSString*)sql error:(NSError * _Nullable __autoreleasing *)outErr withArgumentsInArray:(NSArray*)arrayArgs orDictionary:(NSDictionary *)dictionaryArgs orVAList:(va_list)args {
    /********** 判断环境 ********/
    if (![self databaseExists]) {//数据库是否存在
        return NO;
    }
    if (_isExecutingStatement) {//正在执行 Sql
        [self warnInUse];
        return NO;
    }
    _isExecutingStatement = YES;
    
    int rc                   = 0x00;
    sqlite3_stmt *pStmt      = 0x00;//预处理语句
    FMStatement *cachedStmt  = 0x00;//缓存语句
    
    if (_traceExecution && sql) {
        NSLog(@"%@ executeUpdate: %@", self, sql);
    }
    
    /********** 获取缓存数据 ********/
    if (_shouldCacheStatements) {
        cachedStmt = [self cachedStatementForQuery:sql];//取出缓存的 FMStatement
        pStmt = cachedStmt ? [cachedStmt statement] : 0x00;//获取预处理语句 sqlite3_stmt
        [cachedStmt reset];//重置 sqlite3_stmt
    }
    
    /********** 没有缓存则调用 sqlite3_prepare_v2() 创建 sqlite3_stmt ********/
    if (!pStmt) {
        //对sql语句进行编译，创建 sqlite3_stmt
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
            sqlite3_finalize(pStmt);//失败则释放 sqlite3_stmt
            _isExecutingStatement = NO;
            return NO;
        }
    }
    
    id obj;
    int idx = 0;
    int queryCount = sqlite3_bind_parameter_count(pStmt);
    
    /********** 将变量绑定到 sqlite3_stmt 上 ********/
    if (dictionaryArgs) {
        for (NSString *dictionaryKey in [dictionaryArgs allKeys]) {
            NSString *parameterName = [[NSString alloc] initWithFormat:@":%@", dictionaryKey];
            if (_traceExecution) {
                NSLog(@"%@ = %@", parameterName, [dictionaryArgs objectForKey:dictionaryKey]);
            }
             // 获取参数名的索引： 第几列
            int namedIdx = sqlite3_bind_parameter_index(pStmt, [parameterName UTF8String]);
            FMDBRelease(parameterName);
            if (namedIdx > 0) {
                // 将指定的 value 绑定到 sqlite3_stmt 上 指定的列数
                [self bindObject:[dictionaryArgs objectForKey:dictionaryKey] toColumn:namedIdx inStatement:pStmt];
                idx++;// 计量绑定的参数
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
    }else {
        while (idx < queryCount) {
            if (arrayArgs && idx < (int)[arrayArgs count]) {
                obj = [arrayArgs objectAtIndex:(NSUInteger)idx];
            }else if (args) {
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
            idx++;// 计量绑定的参数
            // 将指定的 value 绑定到 sqlite3_stmt 上 指定的列数
            [self bindObject:obj toColumn:idx inStatement:pStmt];
        }
    }
    if (idx != queryCount) {//如果绑定的参数数目不对，则进行出错处理
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
    
    /** 用于执行有前面 sqlite3_prepare() 创建的 sqlite3_stmt 语句。
     * 该函数执行到结果的第一行可用的位置,继续前进到结果的第二行的话，只需再次调用sqlite3_setp()。
     * 由于执行的SQL不是 SELECT 语句，假设不会返回任何数据，此处 sqlite3_setp() 只调用一次。
     */
    rc = sqlite3_step(pStmt);//执行预处理语句
    if (SQLITE_DONE == rc) {
        //sqlite3_step() 完成执行操作
    }else if (SQLITE_INTERRUPT == rc) {
        //操作被 sqlite3_interupt() 函数中断
        if (_logsErrors) {
            NSLog(@"Error calling sqlite3_step. Query was interrupted (%d: %s) SQLITE_INTERRUPT", rc, sqlite3_errmsg(_db));
            NSLog(@"DB Query: %@", sql);
        }
    }else if (rc == SQLITE_ROW) {
        // sqlite3_step() 已经产生一个行结果 ： 即 sqlite3_stmt 被执行过了一次
        NSString *message = [NSString stringWithFormat:@"A executeUpdate is being called with a query string '%@'", sql];
        if (_logsErrors) {
            NSLog(@"%@", message);
            NSLog(@"DB Query: %@", sql);
        }
        if (outErr) {
            *outErr = [self errorWithMessage:message];
        }
    }else {
        if (outErr) {
            *outErr = [self errorWithMessage:[NSString stringWithUTF8String:sqlite3_errmsg(_db)]];
        }
        
        if (SQLITE_ERROR == rc) {// SQL错误 或 丢失数据库
            if (_logsErrors) {
                NSLog(@"Error calling sqlite3_step (%d: %s) SQLITE_ERROR", rc, sqlite3_errmsg(_db));
                NSLog(@"DB Query: %@", sql);
            }
        }else if (SQLITE_MISUSE == rc) {//不正确的库使用
            if (_logsErrors) {
                NSLog(@"Error calling sqlite3_step (%d: %s) SQLITE_MISUSE", rc, sqlite3_errmsg(_db));
                NSLog(@"DB Query: %@", sql);
            }
        }else {
            if (_logsErrors) {
                NSLog(@"Unknown error calling sqlite3_step (%d: %s) eu", rc, sqlite3_errmsg(_db));
                NSLog(@"DB Query: %@", sql);
            }
        }
    }
    
   
    /**********  针对缓存的处理  ********/
    if (_shouldCacheStatements && !cachedStmt) {//没有缓存，且需要缓存，则创建 FMStatement 对象并缓存
        cachedStmt = [[FMStatement alloc] init];
        [cachedStmt setStatement:pStmt];
        [self setCachedStatement:cachedStmt forQuery:sql];
        FMDBRelease(cachedStmt);
    }
    int closeErrorCode;
    
    if (cachedStmt) {//对缓存数据的处理
        [cachedStmt setUseCount:[cachedStmt useCount] + 1];//计算 sqlite3_stmt 使用过的次数
        closeErrorCode = sqlite3_reset(pStmt);//重置一个pStmt语句对象到它的初始状态，然后准备被重新执行。
    }else {
        //如果不需要缓存，则释放 sqlite3_stmt
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
```

该方法主要做了几件事：
* 1、判断环境：数据库是否存在、或者是否正在执行 Sql 语句；
* 2、如果有缓存，则获取缓存，并重置预处理语句 `sqlite3_stmt`；
* 3、如果没有缓存，则调用 `sqlite3_prepare_v2()` 函数创建 `sqlite3_stmt`；
* 4、将 Sql 语句中占位符 '?' 所对应的变量值通过 `sqlite3_bind_*()` 函数绑定到结构 `sqlite3_stmt` 上；
* 5、调用 `sqlite3_step()` 函数执行预处理语句 `sqlite3_stmt`；
* 6、针对缓存的处理：如果需要则缓存，否则释放预处理语句 `sqlite3_stmt`；

第 4 件事 将 Sql 语句中占位符 '?' 所对应的变量值绑定到`sqlite3_stmt` 主要通过`-bindObject:toColumn:inStatement:`方法完成：

```
- (void)bindObject:(id)obj toColumn:(int)idx inStatement:(sqlite3_stmt*)pStmt {
    if ((!obj) || ((NSNull *)obj == [NSNull null])) {//obj 为 nil
        sqlite3_bind_null(pStmt, idx);
    }else if ([obj isKindOfClass:[NSData class]]) {//绑定 NSData
        const void *bytes = [obj bytes];
        if (!bytes) {
            // 一个空的 NSData 对象, 即 [NSData data].
            // 不要传递空指针，否则sqlite将绑定一个 SQL NULL 而不是一个blob。
            bytes = "";
        }
        sqlite3_bind_blob(pStmt, idx, bytes, (int)[obj length], SQLITE_STATIC);
    }else if ([obj isKindOfClass:[NSDate class]]) {// NSDate
        if (self.hasDateFormatter)
            sqlite3_bind_text(pStmt, idx, [[self stringFromDate:obj] UTF8String], -1, SQLITE_STATIC);
        else
            sqlite3_bind_double(pStmt, idx, [obj timeIntervalSince1970]);
    }else if ([obj isKindOfClass:[NSNumber class]]) {// NSNumber
        if (strcmp([obj objCType], @encode(char)) == 0) {//char 型
            sqlite3_bind_int(pStmt, idx, [obj charValue]);
        }else if (strcmp([obj objCType], @encode(unsigned char)) == 0) {
            sqlite3_bind_int(pStmt, idx, [obj unsignedCharValue]);
        }else if (strcmp([obj objCType], @encode(short)) == 0) {//short 型
            sqlite3_bind_int(pStmt, idx, [obj shortValue]);
        }else if (strcmp([obj objCType], @encode(unsigned short)) == 0) {
            sqlite3_bind_int(pStmt, idx, [obj unsignedShortValue]);
        }else if (strcmp([obj objCType], @encode(int)) == 0) {//int 型
            sqlite3_bind_int(pStmt, idx, [obj intValue]);
        }else if (strcmp([obj objCType], @encode(unsigned int)) == 0) {
            sqlite3_bind_int64(pStmt, idx, (long long)[obj unsignedIntValue]);
        }else if (strcmp([obj objCType], @encode(long)) == 0) {//long 型
            sqlite3_bind_int64(pStmt, idx, [obj longValue]);
        }else if (strcmp([obj objCType], @encode(unsigned long)) == 0) {
            sqlite3_bind_int64(pStmt, idx, (long long)[obj unsignedLongValue]);
        }else if (strcmp([obj objCType], @encode(long long)) == 0) {//long long 型
            sqlite3_bind_int64(pStmt, idx, [obj longLongValue]);
        }else if (strcmp([obj objCType], @encode(unsigned long long)) == 0) {
            sqlite3_bind_int64(pStmt, idx, (long long)[obj unsignedLongLongValue]);
        }else if (strcmp([obj objCType], @encode(float)) == 0) {//float 型
            sqlite3_bind_double(pStmt, idx, [obj floatValue]);
        }else if (strcmp([obj objCType], @encode(double)) == 0) {//double 型
            sqlite3_bind_double(pStmt, idx, [obj doubleValue]);
        }else if (strcmp([obj objCType], @encode(BOOL)) == 0) {//BOOL 型
            sqlite3_bind_int(pStmt, idx, ([obj boolValue] ? 1 : 0));
        }else {//text 型
            sqlite3_bind_text(pStmt, idx, [[obj description] UTF8String], -1, SQLITE_STATIC);
        }
    }else {// text
        sqlite3_bind_text(pStmt, idx, [[obj description] UTF8String], -1, SQLITE_STATIC);
    }
}
```


上述方法的主要功能就是调用 `sqlite3_bind_*()` 函数将值 `obj` 绑定预处理语句 `sqlite3_stmt`：
* `@param obj` 待绑定的值；
* `@param idx` 表中所在列数的索引，需要将 `obj` 绑定到第几列；
* `@parma pStmt` 预处理语句，需要将 obj 绑定到该结构上；

SQLite的 Sql 语句通过绑定变量，减少SQL语句被动态解析的次数，从而提高数据查询和数据操作的效率。

 
 
通过`-bindObject:toColumn:inStatement:`方法内部实现，我们可以发现：SQL语句只能接收的Objective-C对象如 `NSString`、 `NSNumber`、`NSNull`、`NSDate`、`NSData` 等；基本数据类型 `int` 、`NSInteger` 、`float`需要转化为 `NSNumber`；其它Objective-C对象，将使用对象的 `-description` 方法的字符串。

###### 2.4.2 、不得不说的 `-executeUpdateWithFormat:`方法

```
- (BOOL)executeUpdateWithFormat:(NSString*)format, ... {
    va_list args;
    va_start(args, format);
    NSMutableString *sql      = [NSMutableString stringWithCapacity:[format length]];
    NSMutableArray *arguments = [NSMutableArray array];
    [self extractSQL:format argumentsList:args intoString:sql arguments:arguments];
    va_end(args);
    return [self executeUpdate:sql withArgumentsInArray:arguments];
}
```

上述方法执行 Sql 语句之前，先调用了 `-extractSQL:argumentsList:intoString:arguments:`

```
/** 将对应字符串处理成相应的 SQL 语句：
 * 针对 WithFormat:@"INSERT INTO test (name) VALUES (%@)", @"Gus"
 * 将其中的 %s 、%d 、 %@ 等转义序列变为占位符 ? ，然后将 "Gus" 加入到 arguments 中
 */
- (void)extractSQL:(NSString *)sql argumentsList:(va_list)args intoString:(NSMutableString *)cleanedSQL arguments:(NSMutableArray *)arguments;
```

对于需要包含某些特殊字符：使用 '?' 占位符比 `[NSString stringWithFormat:]` 手动构建 SQL 语句更安全：

```
[db executeUpdateWithFormat:@"INSERT INTO Persions (name) VALUES (%@)", @"Gus"];
[db executeUpdate:@"INSERT INTO Persions (name) VALUES (?)", @"Gus”];
```

###### 2.4.3 、其它方法

```
/** 使用 Block 执行多个SQL语句更新 */
- (BOOL)executeStatements:(NSString *)sql withResultBlock:(__attribute__((noescape)) FMDBExecuteStatementsCallbackBlock _Nullable)block;
- (BOOL)executeStatements:(NSString *)sql;

#pragma mark 更新语句信息

/** 获取最后插入一行的主键 rowid
 * 通过 sqlite3_last_insert_rowid()  函数实现
 * @note 如果数据库连接上从未发生过成功的 INSERT，则返回 0
 */
- (sqlite_int64)lastInsertRowId {
    if (_isExecutingStatement) {//正在执行 Sql 语句
        [self warnInUse];
        return NO;
    }
    _isExecutingStatement = YES;
    sqlite_int64 ret = sqlite3_last_insert_rowid(_db);
    _isExecutingStatement = NO;
    return ret;
}

/** 前一个 SQL 语句更改了多少行
 * 通过 sqlite3_changes()  函数实现
 * @note 只计算由INSERT、UPDATE或DELETE语句直接指定的更改的数据库行数
*/
- (int)changes {
    if (_isExecutingStatement) {//正在执行 Sql 语句
        [self warnInUse];
        return 0;
    }
    _isExecutingStatement = YES;
    int ret = sqlite3_changes(_db);
    _isExecutingStatement = NO;
    return ret;
}
```



##### 2.5、查询

FMDB 的 `-executeQuery` 系列方法封装了Sqlite 的 `SELECT` 命令：

```
- (FMResultSet * _Nullable)executeQuery:(NSString*)sql, ...;
- (FMResultSet * _Nullable)executeQuery:(NSString *)sql values:(NSArray * _Nullable)values error:(NSError * _Nullable __autoreleasing *)error;
- (FMResultSet * _Nullable)executeQuery:(NSString *)sql withArgumentsInArray:(NSArray *)arguments;
- (FMResultSet * _Nullable)executeQuery:(NSString *)sql withParameterDictionary:(NSDictionary * _Nullable)arguments;
- (FMResultSet * _Nullable)executeQuery:(NSString *)sql withVAList:(va_list)args;
- (FMResultSet * _Nullable)executeQueryWithFormat:(NSString*)format, ... NS_FORMAT_FUNCTION(1,2);
```

这些方法本质都去执行 `-executeQuery:withArgumentsInArray:orDictionary:orVAList:`

```
- (FMResultSet *)executeQuery:(NSString *)sql withArgumentsInArray:(NSArray*)arrayArgs orDictionary:(NSDictionary *)dictionaryArgs orVAList:(va_list)args {
    /********** 判断环境 ********/
    if (![self databaseExists]) {//判断数据库是否存在
        return 0x00;
    }
    if (_isExecutingStatement) {//是否正在执行 Sql 语句
        [self warnInUse];
        return 0x00;
    }
    _isExecutingStatement = YES;
    
    int rc                  = 0x00;
    sqlite3_stmt *pStmt     = 0x00;//预处理语句
    FMStatement *statement  = 0x00;
    FMResultSet *rs         = 0x00;//结果集
    
    if (_traceExecution && sql) {//打印sql语句
        NSLog(@"%@ executeQuery: %@", self, sql);
    }
    /********** 获取缓存数据 ********/
    if (_shouldCacheStatements) {
        statement = [self cachedStatementForQuery:sql];
        pStmt = statement ? [statement statement] : 0x00;//缓存的预处理语句
        [statement reset];
    }
        
    /********** 没有缓存则调用 sqlite3_prepare() 创建 sqlite3_stmt ********/
    if (!pStmt) {
        //对sql语句进行预处理，创建 sqlite3_stmt
        rc = sqlite3_prepare_v2(_db, [sql UTF8String], -1, &pStmt, 0);
        if (SQLITE_OK != rc) {//错误处理
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
    
    /********** 将变量绑定到 sqlite3_stmt 上 ********/
    id obj;
    int idx = 0;
    int queryCount = sqlite3_bind_parameter_count(pStmt);
    if (dictionaryArgs) {
        for (NSString *dictionaryKey in [dictionaryArgs allKeys]) {
            NSString *parameterName = [[NSString alloc] initWithFormat:@":%@", dictionaryKey];
            if (_traceExecution) {
                NSLog(@"%@ = %@", parameterName, [dictionaryArgs objectForKey:dictionaryKey]);
            }
            // 获取参数名的索引： 第几列
            int namedIdx = sqlite3_bind_parameter_index(pStmt, [parameterName UTF8String]);
            FMDBRelease(parameterName);
            if (namedIdx > 0) {
                // 将指定的 value 绑定到 sqlite3_stmt 上 指定的列数
                [self bindObject:[dictionaryArgs objectForKey:dictionaryKey] toColumn:namedIdx inStatement:pStmt];
                idx++;//计量绑定的参数
            }else {
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
            idx++;//计量绑定的参数
            // 将指定的 value 绑定到 sqlite3_stmt 上 指定的列数
            [self bindObject:obj toColumn:idx inStatement:pStmt];
        }
    }
    if (idx != queryCount) {//如果绑定的参数数目不对，则进行出错处理
        NSLog(@"Error: the bind count is not correct for the # of variables (executeQuery)");
        sqlite3_finalize(pStmt);
        _isExecutingStatement = NO;
        return nil;
    }
    FMDBRetain(statement);
    
    /********** 没有 FMStatement 则创建 FMStatement 对象  ********/
    if (!statement) {
        statement = [[FMStatement alloc] init];
        [statement setStatement:pStmt];
        if (_shouldCacheStatements && sql) {
            //缓存的处理，key为sql语句，值为statement
            [self setCachedStatement:statement forQuery:sql];
        }
    }
    
    /*************** 根据 FMStatement 实例创建一个 FMResultSet *************/
    rs = [FMResultSet resultSetWithStatement:statement usingParentDatabase:self];
    [rs setQuery:sql];
    
    NSValue *openResultSet = [NSValue valueWithNonretainedObject:rs];
    [_openResultSets addObject:openResultSet];
    [statement setUseCount:[statement useCount] + 1];
    FMDBRelease(statement);
    _isExecutingStatement = NO;
    return rs;
}
```

该方法主要做了几件事：
* 1、判断环境：数据库是否存在、或者是否正在执行 Sql 语句；
* 2、如果有缓存，则获取缓存，并重置预处理语句 `sqlite3_stmt`；
* 3、如果没有缓存，则调用 `sqlite3_prepare_v2()` 函数创建 `sqlite3_stmt`；
* 4、将 Sql 语句中占位符 `？` 所对应的变量值通过 `sqlite3_bind_*()` 函数绑定到结构 `sqlite3_stmt` 上；
* 5、如果 `FMStatement` 实例为空，则创建 `FMStatement` 实例，并根据需要缓存该实例；
* 6、根据 `FMStatement` 实例创建一个 `FMResultSet` ，并将`FMResultSet` 实例存储在数组 `_openResultSets` 中；

该方法本质上仅仅封装了预处理语句 `sqlite3_stmt`，但是并没有执行该语句；要获取查询的数据，需要调用 `sqlite3_setp()` 函数执行 `sqlite3_stmt`！FMDB 将执行语句封装在了 `FMResultSet` 的 `-next` 方法中：

```
@implementation FMResultSet

- (BOOL)next {
    return [self nextWithError:nil];
}

- (BOOL)nextWithError:(NSError * _Nullable __autoreleasing *)outErr {
    int rc = sqlite3_step([_statement statement]);//执行查询
    if (rc != SQLITE_ROW) {
        [self close];
    }
    return (rc == SQLITE_ROW);
}
@end
```

由于这些 C 语言变量的内存不被 ARC系统所管理，因此使用 `FMResultSet` 实例完毕后，需要关闭结果集 `[FMResultSet close]` ！


##### 2.6、事务

```
/** 确定当前是否处于事务中 */
@property (nonatomic, readonly) BOOL isInTransaction;

/** 开启事务
 * @note FMDatabase对事务的操作，操作成功返回 YES。失败调用 -lastError、-lastErrorCod 或 -lastErrorMessage 获取失败信息；
 *
 * @warning 与 SQLite 的 BEGIN TRANSACTION 不同，此方法当前执行的是互斥事务，而不是延迟事务；
 *       在FMDB的未来版本中，这种行为可能会改变，因此该方法最终可能采用标准SQLite行为并执行延迟事务。
 *       建议使用 -beginExclusiveTransaction ，保证代码在未来不会被修改。
 */
- (BOOL)beginTransaction {//默认开始互斥事务
    BOOL b = [self executeUpdate:@"begin exclusive transaction"];
    if (b) {
        _isInTransaction = YES;//标记处于事务中
    }
    return b;
}

- (BOOL)beginDeferredTransaction {//开始一个延迟的事务
    BOOL b = [self executeUpdate:@"begin deferred transaction"];
    if (b) {
        _isInTransaction = YES;//标记处于事务中
    }
    return b;
}

- (BOOL)beginImmediateTransaction {//开启即时事务
    BOOL b = [self executeUpdate:@"begin immediate transaction"];
    if (b) {
        _isInTransaction = YES;//标记处于事务中
    }
    return b;
}

- (BOOL)beginExclusiveTransaction {//开始互斥事务
    BOOL b = [self executeUpdate:@"begin exclusive transaction"];
    if (b) {
        _isInTransaction = YES;//标记处于事务中
    }
    return b;
}

/** 提交一个事务
 * 提交一个由 -beginTransaction 或 -beginDeferredTransaction 启动的事务。
 */
- (BOOL)commit {
    BOOL b =  [self executeUpdate:@"commit transaction"];
    if (b) {
        _isInTransaction = NO;//标记事务结束
    }
    return b;
}

/** 回滚事务：把数据库恢复到上次 -commit 或 -rollback 命令时的情况
 * 回滚用 -beginTransaction 或 -beginDeferredTransaction 启动的事务。
 */
- (BOOL)rollback {
    BOOL b = [self executeUpdate:@"rollback transaction"];
    if (b) {
        _isInTransaction = NO;//标记事务结束
    }
    return b;
}
```



###### 2.6.1、事务中的 SavePoint

```
//处理 SavePoint 名字中的特殊字符
static NSString *FMDBEscapeSavePointName(NSString *savepointName) {
    return [savepointName stringByReplacingOccurrencesOfString:@"'" withString:@"''"];
}

/** 创建保存点
 * @param name 保存点的名称
 * @param outErr 双指针 NSError，记录发生的错误；如果为 nil ，则不会返回 NSError；
 * @return 成功返回 YES。如果失败，可以调用 -lastError、 -lastErrorCod 或 -lastErrorMessage 获取失败信息；
 */
- (BOOL)startSavePointWithName:(NSString*)name error:(NSError * _Nullable __autoreleasing *)outErr{
    NSParameterAssert(name);
    NSString *sql = [NSString stringWithFormat:@"savepoint '%@';", FMDBEscapeSavePointName(name)];
    return [self executeUpdate:sql error:outErr withArgumentsInArray:nil orDictionary:nil orVAList:nil];
}

/** 撤销保存点
 */
- (BOOL)releaseSavePointWithName:(NSString*)name error:(NSError * _Nullable __autoreleasing *)outErr {
    NSParameterAssert(name);
    NSString *sql = [NSString stringWithFormat:@"release savepoint '%@';", FMDBEscapeSavePointName(name)];
    return [self executeUpdate:sql error:outErr withArgumentsInArray:nil orDictionary:nil orVAList:nil];
}

/** 回滚到保存点
 */
- (BOOL)rollbackToSavePointWithName:(NSString*)name error:(NSError * _Nullable __autoreleasing *)outErr{
    NSParameterAssert(name);
    NSString *sql = [NSString stringWithFormat:@"rollback transaction to savepoint '%@';", FMDBEscapeSavePointName(name)];
    return [self executeUpdate:sql error:outErr withArgumentsInArray:nil orDictionary:nil orVAList:nil];
}

/** 执行保存点后的代码
 * @param block 要在保存点内执行的代码块
 * @return 错误对应的NSError；如果没有错误返回nil
 */
- (NSError * _Nullable)inSavePoint:(__attribute__((noescape)) void (^)(BOOL *rollback))block{
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
}
```

###### 2.6.2、事务中的检查点 Checkpoint


```
/** 手动配置 WAL 检查点
 * @param name sqlite3_wal_checkpoint_v2() 的数据库名称
 * @param checkpointMode  sqlite3_wal_checkpoint_v2() 的检查点类型
 * @param logFrameCount 如果不为NULL，则将其设置为日志文件中的总帧数，如果检查点由于错误或数据库没有处于WAL模式而无法运行，则将其设置为-1。
 * @param checkpointCount 如果不是NULL,那么这将检查点帧总数日志文件(包括检查点之前任何已经调用的函数)，如果检查点由于错误或数据库不在WAL模式下而无法运行，则为-1。
 * @return 成功返回 YES；
 */
- (BOOL)checkpoint:(FMDBCheckpointMode)checkpointMode error:(NSError * _Nullable *)error;
- (BOOL)checkpoint:(FMDBCheckpointMode)checkpointMode name:(NSString * _Nullable)name error:(NSError * _Nullable *)error;
- (BOOL)checkpoint:(FMDBCheckpointMode)checkpointMode name:(NSString * _Nullable)name logFrameCount:(int * _Nullable)logFrameCount checkpointCount:(int * _Nullable)checkpointCount error:(NSError * _Nullable *)error{
    const char* dbName = [name UTF8String];
    int err = sqlite3_wal_checkpoint_v2(_db, dbName, checkpointMode, logFrameCount, checkpointCount);
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
```

##### 2.7、加密

需要购买 Sqlite [加密扩展](https://www.zetetic.net/sqlcipher/) 才能使用Sqlite 加密功能；

```
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
```

#### 3、`FMDatabaseAdditions`

`FMDatabase` 的分类: 用于对查询结果只返回单个值的方法进行简化；对表、列是否存在；版本号，校验SQL等等功能。

##### 3.1、查询某个值

针对某些确定只有一个返回值的查询语句，不需要通过返回`FMResultSet`并遍历`set`获取


```
/** 使用SQL查询某个值：比如某个人的年纪 "SELECT age FROM Person WHERE Name = ?",@"zhangsan"
 * @param query 要执行的SQL查询
 * @note 被搜索的键最好具有唯一性，得到的结果才能唯一；
 * @note 在 Swift 中不可用
 */
- (int)intForQuery:(NSString*)query, ...;
- (long)longForQuery:(NSString*)query, ...;
- (BOOL)boolForQuery:(NSString*)query, ...;
- (double)doubleForQuery:(NSString*)query, ...;
- (NSString * _Nullable)stringForQuery:(NSString*)query, ...;
- (NSData * _Nullable)dataForQuery:(NSString*)query, ...;
- (NSDate * _Nullable)dateForQuery:(NSString*)query, ...;
```



##### 3.2、数据库、表的概要信息

```
/** 数据库的一些概要信息  */
- (FMResultSet * _Nullable)getSchema{
    FMResultSet *rs = [self executeQuery:@"SELECT type, name, tbl_name, rootpage, sql FROM (SELECT * FROM sqlite_master UNION ALL SELECT * FROM sqlite_temp_master) WHERE type != 'meta' AND name NOT LIKE 'sqlite_%' ORDER BY tbl_name, type DESC, name"];
    return rs;
}

/** 数据库中某张表的一些概要信息 */
- (FMResultSet * _Nullable)getTableSchema:(NSString*)tableName {
    FMResultSet *rs = [self executeQuery:[NSString stringWithFormat: @"pragma table_info('%@')", tableName]];
    return rs;
}

@property (nonatomic) uint32_t applicationID;
@property (nonatomic) uint32_t userVersion;//检索用户版本
```

###### `table_info`

[table_info](http://www.sqlite.org/pragma.html#pragma_table_info) 记录数据库中某张表的每一列信息！

```
table_info(
    cid  integer,//列码
    name text,//该列表头
    type text,//该列的数据类性
    pk    boolean,//是否是主键
    notnull boolean,//要求非空
    dflt_value,//该列默认值
)
```

_eg: 获取表 `Persons`的 `table_info`_

```
FMResultSet *resultSet = [database getTableSchema:@"Persons"];
while ([resultSet next]){
    NSLog(@"Persons Schema ： %@",resultSet.resultDictionary);
}
[resultSet close];

/** 打印日志：
{ cid = 0; "dflt_value" = "<null>";   name = id;       notnull = 0;  pk = 1;  type = INTEGER; }
{ cid = 1; "dflt_value" = "<null>";   name = name;     notnull = 1;  pk = 0;  type = TEXT; }
{ cid = 2; "dflt_value" = "<null>";   name = age;      notnull = 0;  pk = 0;  type = INTEGER; }
{ cid = 3; "dflt_value" = YES;        name = sex;      notnull = 0;  pk = 0;  type = boolean;}
{ cid = 4; "dflt_value" = "datetime('now','localtime')"; name = time; notnull = 0; pk = 0; type = DATETIME;}
{ cid = 5; "dflt_value" = "'无'"; name = hobby;    notnull = 0;  pk = 0;  type = TEXT; }
*/
```

###### `Sql_master`


[Sql_master](http://www.sqlite.org/fileformat.html) 表是 SQLite3 的系统表。该表记录数据库中保存的表、索引、视图、和触发器信息，每一行记录一个项目。在创建一个SQLIte数据库的时候，该表会自动创建。

```
CREATE TABLE sqlite_master(
    type text, //系统表的创建类型，可能值 table, index, view, trigger
    name text, // 表、索引、触发器、视图的名字
    tbl_name text, //对表和视图来说，这个值和name字段一致；对索引和触发器来说是建立在那个表上的表名字
    rootpage integer, // 对表和索引来说是根页的页号；对于视图和触发器，该列值为0或者NULL；
    sql text // 创建该项目的SQL语句
 );
```

_eg: 获取数据库中各个表的 `sqlite_master `_

```
FMResultSet *resultSet = database.getSchema;
while ([resultSet next]){
    NSLog(@"Database Schema ： %@",resultSet.resultDictionary);
}
[resultSet close];

/** 打印日志：
{
    name = Cars; rootpage = 8;"tbl_name" = Cars;type = table;
    sql = "CREATE TABLE Cars (id INTEGER PRIMARY KEY,owners TEXT NOT NULL,brand TEXT,price DOUBLE DEFAULT 0.0,time DATETIME DEFAULT (datetime('now','localtime')),FOREIGN KEY (owners) REFERENCES Persons(name))";
}
{
    name = Persons;rootpage = 6;"tbl_name" = Persons;type = table;
    sql = "CREATE TABLE Persons (id INTEGER PRIMARY KEY,name TEXT UNIQUE NOT NULL,age INTEGER CHECK (age>0),sex boolean DEFAULT YES,time DATETIME DEFAULT (datetime('now','localtime')),hobby TEXT DEFAULT '\U65e0', birthday TEXT)";
}
*/
```

##### 3.3、指定的表、指定的列是否存在？

由于`sqlite_master`表存储所有的数据库项目，所以可以通过该表判断特定的表、视图或者索引是否存在！

```
/** 判断表是否存在 */
- (BOOL)tableExists:(NSString*)tableName {
    tableName = [tableName lowercaseString];
    FMResultSet *rs = [self executeQuery:@"select [sql] from sqlite_master where [type] = 'table' and lower(name) = ?", tableName];
    BOOL returnBool = [rs next];
    [rs close];
    return returnBool;
}
```

由于`table_info`表存储着某表所有的列信息，所以可以通过该表判断特定列是否存在！

```
/** 测试以查看数据库中指定表是否存在指定列  */
- (BOOL)columnExists:(NSString*)columnName inTableWithName:(NSString*)tableName {
    BOOL returnBool = NO;
    tableName  = [tableName lowercaseString];
    columnName = [columnName lowercaseString];
    FMResultSet *rs = [self getTableSchema:tableName];//获取 table_info
    while ([rs next]) {
        if ([[[rs stringForColumn:@"name"] lowercaseString] isEqualToString:columnName]) {
            returnBool = YES;
            break;
        }
    }
    [rs close];
    return returnBool;
}
```



##### 3.4、校验 SQL 语句合法性

```
/** 验证 SQL 语句是否合法
 * @param sql 待验证的SQL语句
 * 内部通过 sqlite3_prepare_v2() 来验证SQL语句，但不返回结果，而是立即调用 sqlite3_finalize()
 * @return 合法则返回 YES
 */
- (BOOL)validateSQL:(NSString*)sql error:(NSError * _Nullable __autoreleasing *)error;
```

#### 4、 `FMResultSet`

`FMResultSet`：代表查询后的结果集，可以通过它遍历查询的结果集，获取出查询得到的数据！

##### 4.1、属性

```
//数据库的实例
@property (nonatomic, retain, nullable) FMDatabase *parentDB;

/** 查询出该结果集所使用的SQL语句 */
@property (atomic, retain, nullable) NSString *query;

/** 将列名称 映射到 数字索引
 * 数字索引从 0 开始
 */
@property (readonly) NSMutableDictionary *columnNameToIndexMap;

/** 结果集中有多少列 */
@property (nonatomic, readonly) int columnCount;

/** 返回列名为键，列内容为值的字典。 键区分大小写  */
@property (nonatomic, readonly, nullable) NSDictionary *resultDictionary;
```

##### 4.2、创建和关闭结果集


```
/** 使用 FMStatement 创建结果集
 * @param statement 要执行的 FMStatement
 * @param aDB 要使用的FMDatabase
 * @return 失败返回 nil
 */
+ (instancetype)resultSetWithStatement:(FMStatement *)statement usingParentDatabase:(FMDatabase*)aDB;

/** 关闭结果集
 * 通常情况下，并不需要关闭 FMResultSet，因为相关的数据库关闭时，FMResultSet 也会被自动关闭。
 */
- (void)close;
```


##### 4.3、遍历结果集

```
/** 检索结果集的下一行。
 * 在尝试访问查询中返回的值之前，必须始终调用 -next 或 -nextWithError ，即使只期望一个值。
 * @return 检索成功返回 YES ;如果到达结果集的末端，则为 NO
 */
- (BOOL)next;
- (BOOL)nextWithError:(NSError * _Nullable __autoreleasing *)outErr;

/** 是否还有下一行数据
 * @return 如果最后一次调用 -next 成功获取另一条记录，则为' YES ';否则为 NO
 * @note 该方法必须跟随 -next 的调用。如果前面的数据库交互不是对 -next 的调用，那么该方法可能返回 NO，不管是否有下一行数据。
 */
- (BOOL)hasAnotherRow;
```


##### 4.4、结果集检索信息

```
/** 结果集中有多少列 */
@property (nonatomic, readonly) int columnCount;

/** 指定列名称的列索引
 * @param columnName 指定列的名称
 * @return 从 0 开始的索引
 */
- (int)columnIndexForName:(NSString*)columnName;

/** 指定列索引的列名称 */
- (NSString * _Nullable)columnNameForIndex:(int)columnIdx;
```

##### 4.5、根据索引获取指定值

```

- (int)intForColumn:(NSString*)columnName;
- (int)intForColumnIndex:(int)columnIdx;

- (long)longForColumn:(NSString*)columnName;
- (long)longForColumnIndex:(int)columnIdx;

- (long long int)longLongIntForColumn:(NSString*)columnName;
- (long long int)longLongIntForColumnIndex:(int)columnIdx;

- (unsigned long long int)unsignedLongLongIntForColumn:(NSString*)columnName;
- (unsigned long long int)unsignedLongLongIntForColumnIndex:(int)columnIdx;

- (BOOL)boolForColumn:(NSString*)columnName;
- (BOOL)boolForColumnIndex:(int)columnIdx;

- (double)doubleForColumn:(NSString*)columnName;
- (double)doubleForColumnIndex:(int)columnIdx;

- (NSString * _Nullable)stringForColumn:(NSString*)columnName;
- (NSString * _Nullable)stringForColumnIndex:(int)columnIdx;

- (NSDate * _Nullable)dateForColumn:(NSString*)columnName;
- (NSDate * _Nullable)dateForColumnIndex:(int)columnIdx;

- (NSData * _Nullable)dataForColumn:(NSString*)columnName;
- (NSData * _Nullable)dataForColumnIndex:(int)columnIdx;

- (const unsigned char * _Nullable)UTF8StringForColumn:(NSString*)columnName;
- (const unsigned char * _Nullable)UTF8StringForColumnName:(NSString*)columnName __deprecated_msg("Use UTF8StringForColumn instead");
- (const unsigned char * _Nullable)UTF8StringForColumnIndex:(int)columnIdx;

/** 返回 NSNumber, NSString, NSData，或NSNull。如果该列是 NULL，则返回 [NSNull NULL]对象。
 *
 * 下述三种调用效果相同：
 *   id result = rs[0];
 *   id result = [rs objectForKeyedSubscript:0];
 *   id result = [rs objectForColumnName:0];
 *
 * 或者：
 *   id result = rs[@"employee_name"];
 *   id result = [rs objectForKeyedSubscript:@"employee_name"];
 *   id result = [rs objectForColumnName:@"employee_name"];
 */
- (id _Nullable)objectForColumn:(NSString*)columnName;
- (id _Nullable)objectForColumnName:(NSString*)columnName __deprecated_msg("Use objectForColumn instead");
- (id _Nullable)objectForColumnIndex:(int)columnIdx;
- (id _Nullable)objectForKeyedSubscript:(NSString *)columnName;
- (id _Nullable)objectAtIndexedSubscript:(int)columnIdx;

/** @warning  如果打算在遍历下一行之后或在关闭结果集之后使用这些数据，请确保首先 copy 这些数据；否则可能出现问题；
 */
- (NSData * _Nullable)dataNoCopyForColumn:(NSString *)columnName NS_RETURNS_NOT_RETAINED;
- (NSData * _Nullable)dataNoCopyForColumnIndex:(int)columnIdx NS_RETURNS_NOT_RETAINED;

/** 判断该列是否为空
 * @return 为空则返回 YES
 */
- (BOOL)columnIndexIsNull:(int)columnIdx;
- (BOOL)columnIsNull:(NSString*)columnName;
```

##### 4.6、对KVC的支持

使用KVC，把数据库中的每一行数据对应到每一个对象，对象的属性要和数据库的列名保持一直。

```
- (void)kvcMagic:(id)object {
    int columnCount = sqlite3_column_count([_statement statement]);//用sqlite3方法取出该表的列数
    //遍历结果集
    int columnIdx = 0;
    for (columnIdx = 0; columnIdx < columnCount; columnIdx++) {
        const char *c = (const char *)sqlite3_column_text([_statement statement], columnIdx);//取出该列的列名
        if (c) {//在列名不为空的情况下，使用KVC给Object的属性赋值
            NSString *s = [NSString stringWithUTF8String:c];
            [object setValue:s forKey:[NSString stringWithUTF8String:sqlite3_column_name([_statement statement], columnIdx)]];
        }
    }
}
```

该方法只能给`NSString`类型的属性赋值 ！




#### 5、`FMDatabaseQueue`

`FMDatabaseQueue`：代表串行队列，对多线程操作提供了支持，保证多线程环境下的数据安全！

```
/** 数据库路径 */
@property (atomic, retain, nullable) NSString *path;

/** 开启标志 */
@property (atomic, readonly) int openFlags;

/** 自定义虚拟文件名称 */
@property (atomic, copy, nullable) NSString *vfsName;
```

##### 5.1、数据库的打开与关闭


```
/** 根据指定的数据库路径路径实例化一个队列
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
- (nullable instancetype)initWithURL:(NSURL * _Nullable)url flags:(int)openFlags vfs:(NSString * _Nullable)vfsName;
- (instancetype)initWithPath:(NSString*)aPath flags:(int)openFlags vfs:(NSString *)vfsName{
    self = [super init];
    if (self != nil) {
        _db = [[[self class] databaseClass] databaseWithPath:aPath];
        FMDBRetain(_db);
        //在创建数据库的时候，默认打开数据库！
        BOOL success = [_db openWithFlags:openFlags vfs:vfsName];
        if (!success) {
            NSLog(@"Could not create database queue for path %@", aPath);
            FMDBRelease(self);
            return 0x00;
        }
        
        _path = FMDBReturnRetained(aPath);
        //GCD 的串行队列
        _queue = dispatch_queue_create([[NSString stringWithFormat:@"fmdb.%@", self] UTF8String], NULL);
        //为 _queue 设置标识数据：指定的键，值为 self 的地址
        dispatch_queue_set_specific(_queue, kDispatchQueueSpecificKey, (__bridge void *)self, NULL);
        _openFlags = openFlags;
        _vfsName = [vfsName copy];
    }
    return self;
}

/** 获取 FMDatabase 类，用于实例化数据库对象。 */
+ (Class)databaseClass {
    return [FMDatabase class];
}

/** 关闭数据库  */
- (void)close {
    FMDBRetain(self);
    dispatch_sync(_queue, ^() {
        [self->_db close];
        FMDBRelease(_db);
        self->_db = 0x00;
    });
    FMDBRelease(self);
}

/** 中断数据库操作  */
- (void)interrupt {
    [[self database] interrupt];
}
```

__注意__：由于 `FMDatabaseQueue` 的任务执行，都是在串行队列 `dispatch_queue` 中同步执行！为防止线程死锁，任何情况下都不能在同一个 `FMDatabaseQueue` 实例下嵌套任务！

##### 5.2、将数据库操作分派到队列

```
/** 在队列上同步执行数据库操作
 * @param block 要在 FMDatabaseQueue 队列上运行的代码
 */
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
        }
    });
    FMDBRelease(self);
}
```

在创建 `FMDatabaseQueue` 时，设定了 `dispatch_queue` 的标识数据，此时通过指定的键可以取出对应的值：
* 如果是主队列、或者全局并发队列，取出的 NULL ，不影响代码执行；
* 如果是在其它 `FMDatabaseQueue` 对象的`dispatch_queue` 中执行，则返回的是其它的实例，不影响代码执行；
* 如果是在当前 `FMDatabaseQueue` 对象的`dispatch_queue` 中执行，则会造成 `dispatch_queue` 的死锁，因此此处断言 `assert(currentSyncQueue!=self)` !

##### 5.3、将事务分派到队列

```
/** 使用事务在 串行dispatch_queue 同步执行数据库操作
 * @note 没有开辟分线程，在当前线程中操作！
 * @note 不可以嵌套使用，否则造成线程死锁；
 */
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

/**默认开始互斥事务  */
- (void)inTransaction:(__attribute__((noescape)) void (^)(FMDatabase *db, BOOL *rollback))block {
    [self beginTransaction:FMDBTransactionExclusive withBlock:block];
}

/** 使用延迟事务在队列上同步执行数据库操作  */
- (void)inDeferredTransaction:(__attribute__((noescape)) void (^)(FMDatabase *db, BOOL *rollback))block {
    [self beginTransaction:FMDBTransactionDeferred withBlock:block];
}

/** 使用互斥事务在队列上同步执行数据库操作。 */
- (void)inExclusiveTransaction:(__attribute__((noescape)) void (^)(FMDatabase *db, BOOL *rollback))block {
    [self beginTransaction:FMDBTransactionExclusive withBlock:block];
}

/** 使用事务立即在队列上同步执行数据库操作。*/
- (void)inImmediateTransaction:(__attribute__((noescape)) void (^)(FMDatabase * _Nonnull, BOOL * _Nonnull))block {
    [self beginTransaction:FMDBTransactionImmediate withBlock:block];
}


/** 使用 保存点机制 同步执行数据库操作
 *
 * @note  不能嵌套操作，因为调用它会从池中拉出另一个数据库，会得到一个死锁。
 *        如果需要嵌套，用 FMDatabase 的 -startSavePointWithName:error: 代替。
 */
- (NSError * _Nullable)inSavePoint:(__attribute__((noescape)) void (^)(FMDatabase *db, BOOL *rollback))block{
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
}


/** 手动配置 WAL 检查点
 * @param name sqlite3_wal_checkpoint_v2() 的数据库名称
 * @param checkpointMode  sqlite3_wal_checkpoint_v2() 的检查点类型
 * @param logFrameCount 如果不为NULL，则将其设置为日志文件中的总帧数，如果检查点由于错误或数据库没有处于WAL模式而无法运行，则将其设置为-1。
 * @param checkpointCount 如果不是NULL,那么这将检查点帧总数日志文件(包括检查点之前任何已经调用的函数)，如果检查点由于错误或数据库不在WAL模式下而无法运行，则为-1。
 * @return 成功返回 YES；
 */
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
```




