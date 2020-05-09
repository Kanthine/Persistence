//
//  Persons.h
//  Persistence
//
//  Created by 苏沫离 on 2020/5/9.
//  Copyright © 2020 苏沫离. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "Car.h"

NS_ASSUME_NONNULL_BEGIN

@interface Persons : NSObject

@property (nonatomic, strong) NSString *name;
@property (nonatomic, assign) BOOL sex;
@property (nonatomic, assign) NSInteger age;
@property (nonatomic, strong) NSString *hobby;
@property (nonatomic, strong) Car *car;

@end


@interface Persons (DAO)

/** 根据唯一键查询唯一值
 */
+ (void)getDateWithName:(NSString *)name completionBlock:(void(^)(NSDate *date))block;

/** 根据某个表头获取表中数据
 */
+ (void)getModelWithKey:(NSString *)key value:(NSString *)value completionBlock:(void(^)(NSArray<Persons *> *models))block;

/** 根据所有数据
 */
+ (void)getAllDatas:(void(^)(NSArray<Persons *> *models))block;

/** 插入
 */
+ (void)insertModel:(Persons *)model;
+ (void)insertModels:(NSArray<Persons *> *)modelArray;

/** 替代
*/
+ (void)replaceModel:(Persons *)model;
+ (void)replaceModels:(NSArray<Persons *> *)modelArray;

/** 更新
*/
+ (void)updateModel:(Persons *)model;

/** 删除表中指定数据
 */
+ (void)deleteModel:(Persons *)model;

@end


NS_ASSUME_NONNULL_END
