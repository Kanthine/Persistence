#import <Foundation/Foundation.h>

FOUNDATION_EXPORT double FMDBVersionNumber;
FOUNDATION_EXPORT const unsigned char FMDBVersionString[];

#import "FMDatabase.h"
#import "FMResultSet.h"
#import "FMDatabaseAdditions.h"
#import "FMDatabaseQueue.h"
#import "FMDatabasePool.h"

/**
 * FMDatabase：代表一个单独的SQLite操作实例，数据库通过它增删改查操作，以及事务和SavePoint、checkpoint 等；
 * FMResultSet：代表查询后的结果集，可以通过它遍历查询的结果集，获取出查询得到的数据；
 * FMDatabaseQueue：代表串行队列，对多线程操作提供了支持，保证多线程环境下的数据安全；
 * FMDatabaseAdditions：是FMDatabase的分类，扩展了查找表是否存在，版本号，表信息等功能；
 * FMDatabasePool：FMDatabase的对象池封装，在多线程环境中访问单个FMDatabase对象容易引起问题，可以通过FMDatabasePool对象池来解决多线程下的访问安全问题；不推荐使用，优先使用FMDatabaseQueue。
 */
