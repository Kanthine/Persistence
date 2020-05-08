//
//  FMDatabaseAdditions.h
//  fmdb
//
//  Created by August Mueller on 10/30/05.
//  Copyright 2005 Flying Meat Inc.. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FMDatabase.h"

NS_ASSUME_NONNULL_BEGIN

/** FMDatabase的分类
 *  用于对查询结果只返回单个值的方法进行简化；对表、列是否存在；版本号，校验SQL等等功能
 */
@interface FMDatabase (FMDatabaseAdditions)

///----------------------------------------
/// @name 使用SQL查询某个值
/// 针对某些确定只有一个返回值的查询语句，不需要通过返回FMResultSet并遍历set获取了
///----------------------------------------


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

// 注意，这里没有 -dataNoCopyForQuery:.
// 这不是一个好事情，因为我们关闭了结果集，然后没有复制的数据会发生什么?谁也知道！


///--------------------------------
/// @name Schema related operations
///--------------------------------

/** 数据库中是否存在指定表?
 * @param tableName 正在查找的表名称
 * @return 找到则返回 YES
 */
- (BOOL)tableExists:(NSString*)tableName;

/** 数据库的一些概要信息
 * 对于每张表，结果集的每一行将包括以下字段:
 *
 * CREATE TABLE sqlite_master(
    type text, //可能值 table, index, view, or trigger
    name text, // 对象的名称
    tbl_name text, //对象引用的表的名称
    rootpage integer, // The page number of the root b-tree page for tables and indices
    sql text // 创建表的 Sql 语句
 );
 * @see [SQLite File Format](http://www.sqlite.org/fileformat.html)
 */
- (FMResultSet * _Nullable)getSchema;

/** 数据库中某张表的一些概要信息
 * {
       cid  integer,//列码
       name text,//该列表头
       type text,//该列的数据类性
       pk    boolean,//是否是主键
       notnull boolean,//要求非空
       dflt_value,//该列默认值
 * }
 * @see [table_info](http://www.sqlite.org/pragma.html#pragma_table_info)
 */
- (FMResultSet * _Nullable)getTableSchema:(NSString*)tableName;

/** 测试以查看数据库中指定表是否存在指定列
 * @param columnName 指定列的名称
 * @param tableName 指定表的名称
 * @return 存在则返回 YES
 */
- (BOOL)columnExists:(NSString*)columnName inTableWithName:(NSString*)tableName;
- (BOOL)columnExists:(NSString*)tableName columnName:(NSString*)columnName __deprecated_msg("Use columnExists:inTableWithName: instead");


/** 验证 SQL 语句是否合法
 * @param sql 待验证的SQL语句
 * 内部通过 sqlite3_prepare_v2() 来验证SQL语句，但不返回结果，而是立即调用 sqlite3_finalize()
 * @return 合法则返回 YES
 */
- (BOOL)validateSQL:(NSString*)sql error:(NSError * _Nullable __autoreleasing *)error;


///-----------------------------------
/// @name Application identifier tasks
///-----------------------------------

/** application ID
 */
@property (nonatomic) uint32_t applicationID;

#if TARGET_OS_MAC && !TARGET_OS_IPHONE

/** application ID
 */
@property (nonatomic, retain) NSString *applicationIDString;

#endif

///-----------------------------------
/// @name user version identifier tasks
///-----------------------------------

/** 检索用户版本
 * 内部实现了 setter 、getter 方法；
 */
@property (nonatomic) uint32_t userVersion;

@end

NS_ASSUME_NONNULL_END
