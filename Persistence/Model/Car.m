//
//  Car.m
//  Persistence
//
//  Created by 苏沫离 on 2020/5/9.
//  Copyright © 2020 苏沫离. All rights reserved.
//

#import "Car.h"
#import "DatabaseManagement.h"


@implementation Car

@end

@implementation Car (DAO)

+ (void)creatTableWithDatabase:(FMDatabase *)database{
    if (![database tableExists:@"Cars"]){
        [database executeUpdate:@"CREATE TABLE Cars (id INTEGER PRIMARY KEY,owners TEXT NOT NULL,brand TEXT,price DOUBLE DEFAULT 0.0,time DATETIME DEFAULT (datetime('now','localtime')),FOREIGN KEY (owners) REFERENCES Persons(name))"];
    }
}

+ (void)getDateWithName:(NSString *)owners completionBlock:(void(^)(NSDate *date))block{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase * _Nonnull database, BOOL * _Nonnull rollback) {
        NSDate *date = [database dateForQuery:@"SELECT time FROM Cars WHERE owners = ?",owners];
        dispatch_async(dispatch_get_main_queue(), ^{
             block(date);
         });
        
        NSString *string = [database stringForQuery:@"SELECT time FROM Cars WHERE owners = ?",owners];
         NSLog(@"string ---- %@",string);
    }];
}

+ (void)getModelWithKey:(NSString *)key value:(NSString *)value completionBlock:(void(^)(NSArray<Car *> *models))block{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        
        NSMutableArray *array = [NSMutableArray array];
        
        FMResultSet *resultSet = [database executeQuery:@"SELECT * FROM Cars WHERE ? = ?",key,value];
        while ([resultSet next]){
            Car *model = [[Car alloc] init];
            model.owners = [resultSet stringForColumn:@"owners"];
            model.brand = [resultSet stringForColumn:@"brand"];
            model.price = [resultSet doubleForColumn:@"price"];
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
+ (void)getAllDatas:(void(^)(NSArray<Car *> *models))block{
    
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        NSMutableArray *array = [NSMutableArray array];
        
        FMResultSet *resultSet = [database executeQuery:@"SELECT * FROM Cars"];
        while ([resultSet next]){
            Car *model = [[Car alloc] init];
            model.owners = [resultSet stringForColumn:@"owners"];
            model.brand = [resultSet stringForColumn:@"brand"];
            model.price = [resultSet doubleForColumn:@"price"];
            [array addObject:model];
        }
        [resultSet close];
        
       dispatch_async(dispatch_get_main_queue(), ^{
            block(array);
        });
    }];
}

+ (void)insertModel:(Car *)model{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [self creatTableWithDatabase:database];
        
        BOOL result = [database executeUpdate:@"INSERT INTO Cars (owners,brand,price) VALUES (? , ? , ?)" ,model.owners,model.brand,@(model.price)];
        if (!result) {
            NSLog(@"error ===== %@",database.lastError);
            NSLog(@"model ===== %@",model);
        }
    }];
}

+ (void)insertModels:(NSArray<Car *> *)modelArray{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [self creatTableWithDatabase:database];
        [modelArray enumerateObjectsUsingBlock:^(Car * _Nonnull model, NSUInteger idx, BOOL * _Nonnull stop) {
            BOOL result = [database executeUpdate:@"INSERT INTO Cars (owners,brand,price) VALUES (? , ? , ?)" ,model.owners,model.brand,@(model.price)];
            if (!result) {
                NSLog(@"error ===== %@",database.lastError);
                NSLog(@"model ===== %@",model);
            }
        }];
    }];
}

+ (void)replaceModel:(Car *)model{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [self creatTableWithDatabase:database];
        
        [database executeUpdate:@"REPLACE INTO Cars (owners,brand,price) VALUES (? , ? , ?)" ,model.owners,model.brand,@(model.price)];

    }];
}

+ (void)replaceModels:(NSArray<Car *> *)modelArray{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [self creatTableWithDatabase:database];
        
        NSMutableString *string = [[NSMutableString alloc] init];
        [modelArray enumerateObjectsUsingBlock:^(Car * _Nonnull model, NSUInteger idx, BOOL * _Nonnull stop) {
            if (idx) {
                [string appendFormat:@",('%@' , '%@' , '%@')",model.owners,model.brand,@(model.price)];
            }else{
                [string appendFormat:@"('%@' , '%@' , '%@')",model.owners,model.brand,@(model.price)];
            }
        }];
        NSString *sql = [NSString stringWithFormat:@"REPLACE INTO Cars (owners,brand,price) VALUES %@",string];
        BOOL result = [database executeUpdate:sql];
        if (!result) {
            NSLog(@"error ===== %@",database.lastError);
        }
    }];
}

/** 更新
*/
+ (void)updateModel:(Car *)model{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {

        BOOL result = [database executeUpdate:@"UPDATE Cars SET brand = ?,price = ? WHERE owners = ?" ,model.brand,@(model.price),model.owners];
        if (!result) {
            NSLog(@"error ===== %@",database.lastError);
            NSLog(@"model ===== %@",model);
        }
    }];
}

+ (void)deleteModel:(Car *)model{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [database executeUpdate:@"DELETE FROM Cars WHERE owners = ?",model.owners];
    }];
}

@end
