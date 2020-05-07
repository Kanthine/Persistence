#import <Foundation/Foundation.h>

FOUNDATION_EXPORT double FMDBVersionNumber;
FOUNDATION_EXPORT const unsigned char FMDBVersionString[];

#import "FMDatabase.h"
#import "FMResultSet.h"
#import "FMDatabaseAdditions.h"
#import "FMDatabaseQueue.h"
#import "FMDatabasePool.h"

/**
 * FMDatabase：代表一个单独的SQLite操作实例，数据库通过它增删改查操作；
 * FMResultSet：代表查询后的结果集；
 * FMDatabaseQueue：代表串行队列，对多线程操作提供了支持；
 * FMDatabaseAdditions：本类用于扩展FMDatabase，用于查找表是否存在，版本号等功能；
 * FMDatabasePool：此方式官方是不推荐使用，代表是任务池，也是对多线程提供了支持。
 */
