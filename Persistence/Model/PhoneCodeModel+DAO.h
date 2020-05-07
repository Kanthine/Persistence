//
//  PhoneCodeModel+DAO.h
//  Persistence
//
//  Created by 苏沫离 on 2020/4/29.
//  Copyright © 2020 苏沫离. All rights reserved.
//

#import "PhoneCodeModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface PhoneCodeModel (DAO)

/** 异步操作 */

/** 创建一张表
 */
+ (void)creatTable;

/** 销毁一张表
 */
+ (void)dropTable;

/** 根据某个表头获取表中数据
 */
+ (void)getModelWithKey:(NSString *)key value:(NSString *)value completionBlock:(void(^)(NSArray<PhoneCodeModel *> *models))block;

/** 插入
 */
+ (void)insertModel:(PhoneCodeModel *)model;
+ (void)insertModels:(NSArray<PhoneCodeModel *> *)modelArray;

/** 替代
*/
+ (void)replaceModel:(PhoneCodeModel *)model;
+ (void)replaceModels:(NSArray<PhoneCodeModel *> *)modelArray;

/** 更新
*/
+ (void)updateModel:(PhoneCodeModel *)model;

/** 删除表中指定数据
 */
+ (void)deleteModel:(PhoneCodeModel *)model;

@end

NS_ASSUME_NONNULL_END
