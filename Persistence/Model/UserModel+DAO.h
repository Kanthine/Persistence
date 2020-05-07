//
//  UserModel+DAO.h
//  Persistence
//
//  Created by 苏沫离 on 2020/4/29.
//  Copyright © 2020 苏沫离. All rights reserved.
//

#import "UserModel.h"
#import "FMDB.h"

NS_ASSUME_NONNULL_BEGIN

@interface UserModel (DAO)

/** 创建一张表
 */
+ (void)creatTable;

/** 销毁一张表
 */
+ (void)dropTable;

/** 根据群组id获取表中一组数据
 */
+ (void)getModelWithKey:(NSString *)key value:(NSString *)value completionBlock:(void(^)(UserModel *model))block;

/** 根据群组id 向表中插入一组数据
 */
+ (void)insertModel:(UserModel *)model;

/** 更新一个 model
 */
+ (void)updateModel:(UserModel *)model;

/** 根据群组id删除表中指定数据
 */
+ (void)deleteModel:(UserModel *)model;

@end


@interface UserInfoModel (DAO)

/** 创建一张表
 */
+ (void)creatTable;

/** 销毁一张表
 */
+ (void)dropTable;

/** 根据群组id获取表中一组数据
 */
+ (UserInfoModel *)getUserInfoWithNumberId:(NSString *)numberId Database:(FMDatabase *)database;

/** 根据群组id 向表中插入一组数据
 */
+ (void)insertUserInfoWithNumberId:(NSString *)numberId Database:(FMDatabase *)database Model:(UserInfoModel *)model;

/** 根据群组id删除表中指定数据
 */
+ (void)deleteUserInfoWithNumberId:(NSString *)numberId Database:(FMDatabase *)database;

@end


NS_ASSUME_NONNULL_END
