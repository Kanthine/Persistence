//
//  PhoneCodeModel+DAO.m
//  Persistence
//
//  Created by 苏沫离 on 2020/4/29.
//  Copyright © 2020 苏沫离. All rights reserved.
//

#import "PhoneCodeModel+DAO.h"
#import "DatabaseManagement.h"

@implementation PhoneCodeModel (DAO)

+ (void)creatTable{
    [DatabaseManagement databaseCurrentThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        if (![database tableExists:@"PhoneCodeModel"]){
            [database executeUpdate:@"CREATE TABLE PhoneCodeModel (id INTEGER PRIMARY KEY,phoneCode TEXT UNIQUE NOT NULL,countryCode TEXT, countryPinYin TEXT, countryEnglish TEXT, countryChinese TEXT)"];
        }
    }];
}

+ (void)dropTable{
    [DatabaseManagement emptyTableWithName:@"PhoneCodeModel"];
}

+ (void)getNameWithPhoneCode:(NSString *)value completionBlock:(void(^)(NSString *name))block{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase * _Nonnull database, BOOL * _Nonnull rollback) {
        NSString *string = [database stringForQuery:@"SELECT countryChinese FROM PhoneCodeModel WHERE phoneCode = ?",value];
        dispatch_async(dispatch_get_main_queue(), ^{
             block(string);
         });
    }];
}

+ (void)getModelWithKey:(NSString *)key value:(NSString *)value completionBlock:(void(^)(NSArray<PhoneCodeModel *> *models))block{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        
        NSMutableArray *array = [NSMutableArray array];
        
        FMResultSet *resultSet = [database executeQuery:@"SELECT * FROM PhoneCodeModel WHERE ? = ?",key,value];
        while ([resultSet next]){
            PhoneCodeModel *model = [[PhoneCodeModel alloc] init];
            model.countryCode = [resultSet stringForColumn:@"countryCode"];
            model.countryPinYin = [resultSet stringForColumn:@"countryPinYin"];
            model.countryEnglish = [resultSet stringForColumn:@"countryEnglish"];
            model.phoneCode = [resultSet stringForColumn:@"phoneCode"];
            model.countryChinese = [resultSet stringForColumn:@"countryChinese"];
            [array addObject:model];
        }
        [resultSet close];
        
       dispatch_async(dispatch_get_main_queue(), ^{
            block(array);
        });
    }];
}

/** 根据所有数据
 */
+ (void)getAllDatas:(void(^)(NSArray<PhoneCodeModel *> *models))block{
    
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        NSMutableArray *array = [NSMutableArray array];
        
        FMResultSet *resultSet = [database executeQuery:@"SELECT * FROM PhoneCodeModel"];
        while ([resultSet next]){
            PhoneCodeModel *model = [[PhoneCodeModel alloc] init];
            model.countryCode = [resultSet stringForColumn:@"countryCode"];
            model.countryPinYin = [resultSet stringForColumn:@"countryPinYin"];
            model.countryEnglish = [resultSet stringForColumn:@"countryEnglish"];
            model.phoneCode = [resultSet stringForColumn:@"phoneCode"];
            model.countryChinese = [resultSet stringForColumn:@"countryChinese"];
            [array addObject:model];
        }
        [resultSet close];
        
       dispatch_async(dispatch_get_main_queue(), ^{
            block(array);
        });
    }];
}

+ (void)insertModel:(PhoneCodeModel *)model{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        BOOL result = [database executeUpdate:@"INSERT INTO PhoneCodeModel (phoneCode,countryCode,countryPinYin,countryEnglish,countryChinese) VALUES (? , ? , ? , ? , ?)" ,model.phoneCode,model.countryCode,model.countryPinYin,model.countryEnglish,model.countryChinese];
        if (!result) {
            NSLog(@"error ===== %@",database.lastError);
            NSLog(@"model ===== %@",model);
        }
    }];
}

+ (void)insertModels:(NSArray<PhoneCodeModel *> *)modelArray{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [modelArray enumerateObjectsUsingBlock:^(PhoneCodeModel * _Nonnull model, NSUInteger idx, BOOL * _Nonnull stop) {
            BOOL result = [database executeUpdate:@"INSERT INTO PhoneCodeModel (phoneCode,countryCode,countryPinYin,countryEnglish,countryChinese) VALUES (? , ? , ? , ? , ?)" ,model.phoneCode,model.countryCode,model.countryPinYin,model.countryEnglish,model.countryChinese];
            if (!result) {
                NSLog(@"error ===== %@",database.lastError);
                NSLog(@"model ===== %@",model);
            }
        }];
    }];
}

+ (void)replaceModel:(PhoneCodeModel *)model{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [database executeUpdate:@"REPLACE INTO PhoneCodeModel (phoneCode,countryCode,countryPinYin,countryEnglish,countryChinese) VALUES (? , ? , ? , ? , ?)",
         model.phoneCode,model.countryCode,model.countryPinYin,model.countryEnglish,model.countryChinese];
    }];
}

+ (void)replaceModels:(NSArray<PhoneCodeModel *> *)modelArray{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [modelArray enumerateObjectsUsingBlock:^(PhoneCodeModel * _Nonnull model, NSUInteger idx, BOOL * _Nonnull stop) {
            [database executeUpdate:@"REPLACE INTO PhoneCodeModel (phoneCode,countryCode,countryPinYin,countryEnglish,countryChinese) VALUES (? , ? , ? , ? , ?)",
             model.phoneCode,model.countryCode,model.countryPinYin,model.countryEnglish,model.countryChinese];
        }];
    }];
}

/** 更新
*/
+ (void)updateModel:(PhoneCodeModel *)model{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        
        BOOL result = [database executeUpdate:@"UPDATE PhoneCodeModel SET countryCode = ?,countryPinYin = ?,countryEnglish = ?,countryChinese = ? WHERE phoneCode = ?" ,model.countryCode,model.countryPinYin,model.countryEnglish,model.countryChinese,model.phoneCode];
        if (!result) {
            NSLog(@"error ===== %@",database.lastError);
            NSLog(@"model ===== %@",model);
        }
    }];
}

+ (void)deleteModel:(PhoneCodeModel *)model{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [database executeUpdate:@"DELETE FROM PhoneCodeModel WHERE phoneCode = ?",model.phoneCode];
    }];
}

@end
