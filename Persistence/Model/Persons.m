//
//  Persons.m
//  Persistence
//
//  Created by 苏沫离 on 2020/5/9.
//  Copyright © 2020 苏沫离. All rights reserved.
//

#import "Persons.h"
#import "DatabaseManagement.h"


@implementation Persons

@end


@implementation Persons (DAO)

+ (void)creatTableWithDatabase:(FMDatabase *)database{
    if (![database tableExists:@"Persons"]){
        [database executeUpdate:@"CREATE TABLE Persons (id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT UNIQUE NOT NULL,age INTEGER CHECK (age>0),sex boolean DEFAULT YES,time DATETIME DEFAULT (datetime('now','localtime')),hobby TEXT DEFAULT '无')"];
    }
}

+ (void)getDateWithName:(NSString *)name completionBlock:(void(^)(NSDate *date))block{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase * _Nonnull database, BOOL * _Nonnull rollback) {
        NSDate *date = [database dateForQuery:@"SELECT time FROM Persons WHERE name = ?",name];
        dispatch_async(dispatch_get_main_queue(), ^{
             block(date);
         });
        
        NSString *string = [database stringForQuery:@"SELECT time FROM Persons WHERE name = ?",name];
        NSLog(@"string ===== %@",string);
    }];
}

+ (void)getModelWithKey:(NSString *)key value:(NSString *)value completionBlock:(void(^)(NSArray<Persons *> *models))block{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        
        NSMutableArray *array = [NSMutableArray array];
        
        FMResultSet *resultSet = [database executeQuery:@"SELECT * FROM Persons WHERE ? = ?",key,value];
        while ([resultSet next]){
            Persons *model = [[Persons alloc] init];
            model.name = [resultSet stringForColumn:@"name"];
            model.age = [resultSet intForColumn:@"age"];
            model.sex = [resultSet boolForColumn:@"sex"];
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
+ (void)getAllDatas:(void(^)(NSArray<Persons *> *models))block{
    
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        NSMutableArray *array = [NSMutableArray array];
        
        FMResultSet *resultSet = [database executeQuery:@"SELECT * FROM Persons"];
        while ([resultSet next]){
            Persons *model = [[Persons alloc] init];
            model.name = [resultSet stringForColumn:@"name"];
            model.age = [resultSet intForColumn:@"age"];
            model.sex = [resultSet boolForColumn:@"sex"];
            [array addObject:model];
        }
        [resultSet close];
        
       dispatch_async(dispatch_get_main_queue(), ^{
            block(array);
        });
    }];
}

+ (void)insertModel:(Persons *)model{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [self creatTableWithDatabase:database];        
        BOOL result = [database executeUpdate:@"INSERT INTO Persons (name,age,sex) VALUES (? , ? , ?)" ,model.name,@(model.age),@(model.sex)];
        if (!result) {
            NSLog(@"error ===== %@",database.lastError);
            NSLog(@"model ===== %@",model);
        }
    }];
}

+ (void)insertModels:(NSArray<Persons *> *)modelArray{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [self creatTableWithDatabase:database];
        
        [modelArray enumerateObjectsUsingBlock:^(Persons * _Nonnull model, NSUInteger idx, BOOL * _Nonnull stop) {
            BOOL result = [database executeUpdate:@"INSERT INTO Persons (name,age,sex) VALUES (? , ? , ?)" ,model.name,@(model.age),@(model.sex)];
            if (!result) {
                NSLog(@"error ===== %@",database.lastError);
                NSLog(@"model ===== %@",model);
            }
        }];
    }];
}

+ (void)replaceModel:(Persons *)model{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [self creatTableWithDatabase:database];
        
        [database executeUpdate:@"REPLACE INTO Persons (name,age,sex) VALUES (? , ? , ?)" ,model.name,@(model.age),@(model.sex)];
    }];
}

+ (void)replaceModels:(NSArray<Persons *> *)modelArray{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [self creatTableWithDatabase:database];
        
        NSMutableString *string = [[NSMutableString alloc] init];
        [modelArray enumerateObjectsUsingBlock:^(Persons * _Nonnull model, NSUInteger idx, BOOL * _Nonnull stop) {
            if (idx) {
                [string appendFormat:@",('%@' , '%@' , '%@')",model.name,@(model.age),@(model.sex)];
            }else{
                [string appendFormat:@"('%@' , '%@' , '%@')",model.name,@(model.age),@(model.sex)];
            }
        }];
        NSString *sql = [NSString stringWithFormat:@"REPLACE INTO Persons (name,age,sex) VALUES %@",string];
        BOOL result = [database executeUpdate:sql];
        if (!result) {
            NSLog(@"error ===== %@",database.lastError);
        }
    }];
}

/** 更新
*/
+ (void)updateModel:(Persons *)model{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        BOOL result = [database executeUpdate:@"UPDATE Persons SET age = ?,sex = ? WHERE name = ?" ,@(model.age),@(model.sex),model.name];
        if (!result) {
            NSLog(@"error ===== %@",database.lastError);
            NSLog(@"model ===== %@",model);
        }
    }];
}

+ (void)deleteModel:(Persons *)model{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [database executeUpdate:@"DELETE FROM Persons WHERE name = ?",model.name];
    }];
}

@end
