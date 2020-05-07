//
//  UserModel+DAO.m
//  Persistence
//
//  Created by 苏沫离 on 2020/4/29.
//  Copyright © 2020 苏沫离. All rights reserved.
//

#import "UserModel+DAO.h"
#import "DatabaseManagement.h"


@implementation UserModel (DAO)

+ (void)creatTable{
    [DatabaseManagement databaseCurrentThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        if (![database tableExists:@"UserModel"]){
            [database executeUpdate:@"CREATE TABLE UserModel (id INTEGER PRIMARY KEY,numberId TEXT UNIQUE NOT NULL)"];
        }
    }];
}

+ (void)dropTable{
    [DatabaseManagement databaseCurrentThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [database executeUpdate:@"DROP TABLE IF EXISTS UserModel"];
        [database executeUpdate:@"CREATE TABLE UserModel (id INTEGER PRIMARY KEY,numberId TEXT UNIQUE NOT NULL)"];
    }];
}

+ (void)getModelWithKey:(NSString *)key value:(NSString *)value completionBlock:(void(^)(UserModel *model))block{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        UserModel *model = [[UserModel alloc] init];
        model.userInfo = [UserInfoModel getUserInfoWithNumberId:value Database:database];
        if (model.userInfo && model.userInfo.numberId){
            dispatch_async(dispatch_get_main_queue(), ^{
                block(model);
            });
        }
    }];
}

+ (void)insertModel:(UserModel *)model{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [database executeUpdate:@"REPLACE INTO UserModel (numberId) VALUES (?)",model.userInfo.numberId];
        [UserInfoModel insertUserInfoWithNumberId:model.userInfo.numberId Database:database Model:model.userInfo];
    }];
}

+ (void)updateModel:(UserModel *)model{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [UserInfoModel insertUserInfoWithNumberId:model.userInfo.numberId Database:database Model:model.userInfo];
    }];
}

+ (void)deleteModel:(UserModel *)model{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [database executeUpdate:@"DELETE FROM UserModel WHERE numberId = ?",model.userInfo.numberId];
        [UserInfoModel deleteUserInfoWithNumberId:model.userInfo.numberId Database:database];
    }];
}

@end








@implementation UserInfoModel (DAO)

+ (void)creatTable{
    [DatabaseManagement databaseCurrentThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        if (![database tableExists:@"UserInfoModel"]){
            [database executeUpdate:@"CREATE TABLE UserInfoModel (id INTEGER PRIMARY KEY,numberId TEXT UNIQUE NOT NULL,headPath TEXT, age TEXT, sex TEXT, nickName TEXT, userMobile TEXT)"];
        }
    }];
}

+ (void)dropTable{
    [DatabaseManagement databaseCurrentThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [database executeUpdate:@"DROP TABLE IF EXISTS UserInfoModel"];
        [database executeUpdate:@"CREATE TABLE UserInfoModel (id INTEGER PRIMARY KEY,numberId TEXT UNIQUE NOT NULL,headPath TEXT,age TEXT, sex TEXT, nickName TEXT, userMobile TEXT)"];
    }];
}

+ (UserInfoModel *)getUserInfoWithNumberId:(NSString *)numberId Database:(FMDatabase *)database{
    UserInfoModel *model = nil;
    FMResultSet *resultSet = [database executeQuery:@"SELECT * FROM UserInfoModel WHERE numberId = ?",numberId];
    while ([resultSet next]){
        model = [[UserInfoModel alloc] init];
        model.numberId = [resultSet stringForColumn:@"numberId"];
        model.headPath = [resultSet stringForColumn:@"headPath"];
        model.age = [resultSet stringForColumn:@"age"];
        model.sex = [resultSet stringForColumn:@"sex"];
        model.nickName = [resultSet stringForColumn:@"nickName"];
        model.userMobile = [resultSet stringForColumn:@"userMobile"];
    }
    return model;
}

+ (void)insertUserInfoWithNumberId:(NSString *)numberId Database:(FMDatabase *)database Model:(UserInfoModel *)model{
    if (numberId && model){
        [database executeUpdate:@"REPLACE INTO UserInfoModel (numberId,headPath,age,sex,nickName,userMobile) VALUES (? , ? , ? , ? , ? , ? , ? , ? , ?)",
         numberId,model.headPath,model.age,model.sex,model.nickName,model.userMobile];
    }
}

+ (void)deleteUserInfoWithNumberId:(NSString *)numberId Database:(FMDatabase *)database{
    [database executeUpdate:@"DELETE FROM UserInfoModel WHERE numberId = ?",numberId];
}

@end
