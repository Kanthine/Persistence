#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifndef __has_feature      // Optional.
#define __has_feature(x) 0 // Compatibility with non-clang compilers.
#endif

#ifndef NS_RETURNS_NOT_RETAINED
#if __has_feature(attribute_ns_returns_not_retained)
#define NS_RETURNS_NOT_RETAINED __attribute__((ns_returns_not_retained))
#else
#define NS_RETURNS_NOT_RETAINED
#endif
#endif

@class FMDatabase;
@class FMStatement;

/** 在 FMDatabase 查询的结果集
 */
@interface FMResultSet : NSObject

//数据库的实例
@property (nonatomic, retain, nullable) FMDatabase *parentDB;

///-----------------
/// @name Properties
///-----------------

/** 查询出该结果集所使用的SQL语句 */
@property (atomic, retain, nullable) NSString *query;

/** 将列名称 映射到 数字索引
 * 数字索引从 0 开始
 */
@property (readonly) NSMutableDictionary *columnNameToIndexMap;

/** `FMStatement` used by result set. */
@property (atomic, retain, nullable) FMStatement *statement;

///------------------------------------
/// @name 创建和关闭结果集
///------------------------------------

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

///---------------------------------------
/// @name 遍历结果集
///---------------------------------------

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

///---------------------------------------------
/// @name 从结果集检索信息
///---------------------------------------------

/** 结果集中有多少列 */
@property (nonatomic, readonly) int columnCount;

/** 指定列名称的列索引
 * @param columnName 指定列的名称
 * @return 从 0 开始的索引
 */
- (int)columnIndexForName:(NSString*)columnName;

/** 指定列索引的列名称 */
- (NSString * _Nullable)columnNameForIndex:(int)columnIdx;

#pragma mark - 根据指定的列名称或者列索引，获取某一行中该列的值

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


/** 返回列名为键，列内容为值的字典。 键区分大小写  */
@property (nonatomic, readonly, nullable) NSDictionary *resultDictionary;
- (NSDictionary * _Nullable)resultDict __deprecated_msg("Use resultDictionary instead");


/** 使用KVC，把数据库中的每一行数据对应到每一个对象，对象的属性要和数据库的列名保持一直
 * @note 只能给NSString类型的属性赋值
 */
- (void)kvcMagic:(id)object;

 
@end

NS_ASSUME_NONNULL_END
