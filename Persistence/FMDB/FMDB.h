#import <Foundation/Foundation.h>

FOUNDATION_EXPORT double FMDBVersionNumber;
FOUNDATION_EXPORT const unsigned char FMDBVersionString[];

#import "FMDatabase.h"
#import "FMResultSet.h"
#import "FMDatabaseAdditions.h"
#import "FMDatabaseQueue.h"
#import "FMDatabasePool.h"

/**
 * FMStatement ：是对 SQLite 的预处理语句 sqlite3_stmt 的封装，并增加了缓存该语句的功能；
 * FMDatabase：代表一个单独的SQLite操作实例，打开或者关闭数据库，对数据库执行增、删、改、查等操作，以及以事务方式处理数据等；
 * FMResultSet：封装了查询后的结果集，通过 -next 获取查询的数据；
 * FMDatabaseQueue：将对数据库的所有操作，都封装在串行队列执行！避免数据竞态问题，保证多线程环境下的数据安全；
 * FMDatabaseAdditions：是FMDatabase的分类，扩展了查找表是否存在，版本号，表信息等功能；
 * FMDatabasePool：FMDatabase的对象池封装，在多线程环境中访问单个FMDatabase对象容易引起问题，可以通过FMDatabasePool对象池来解决多线程下的访问安全问题；不推荐使用，优先使用FMDatabaseQueue。
 */


/**
 
 


 
 
 */
