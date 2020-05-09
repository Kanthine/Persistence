//
//  Car.h
//  Persistence
//
//  Created by 苏沫离 on 2020/5/9.
//  Copyright © 2020 苏沫离. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Car : NSObject

@property (nonatomic, strong) NSString *owners;
@property (nonatomic, strong) NSString *brand;
@property (nonatomic, assign) double price;

@end

@interface Car (DAO)

/** 根据唯一键查询唯一值
 */
+ (void)getDateWithName:(NSString *)name completionBlock:(void(^)(NSDate *date))block;

/** 根据某个表头获取表中数据
 */
+ (void)getModelWithKey:(NSString *)key value:(NSString *)value completionBlock:(void(^)(NSArray<Car *> *models))block;

/** 根据所有数据
 */
+ (void)getAllDatas:(void(^)(NSArray<Car *> *models))block;

/** 插入
 */
+ (void)insertModel:(Car *)model;
+ (void)insertModels:(NSArray<Car *> *)modelArray;

/** 替代
*/
+ (void)replaceModel:(Car *)model;
+ (void)replaceModels:(NSArray<Car *> *)modelArray;

/** 更新
*/
+ (void)updateModel:(Car *)model;

/** 删除表中指定数据
 */
+ (void)deleteModel:(Car *)model;

@end


NS_ASSUME_NONNULL_END
