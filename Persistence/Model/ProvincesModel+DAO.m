//
//  ProvincesModel+DAO.m
//  Persistence
//
//  Created by 苏沫离 on 2020/4/29.
//  Copyright © 2020 苏沫离. All rights reserved.
//

#import "ProvincesModel+DAO.h"
#import "DatabaseManagement.h"

@implementation ProvincesModel (DAO)

+ (void)creatTable{
    [DatabaseManagement databaseCurrentThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        if (![database tableExists:@"ProvincesModel"]){
            [database executeUpdate:@"CREATE TABLE ProvincesModel (id INTEGER PRIMARY KEY,regionId TEXT UNIQUE NOT NULL,regionName TEXT, regionType TEXT, parentId TEXT, agencyId TEXT)"];
        }
    }];
}

+ (void)dropTable{
    [DatabaseManagement databaseCurrentThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [database executeUpdate:@"DROP TABLE IF EXISTS ProvincesModel"];
        [database executeUpdate:@"CREATE TABLE ProvincesModel (id INTEGER PRIMARY KEY,regionId TEXT UNIQUE NOT NULL,regionName TEXT, regionType TEXT, parentId TEXT, agencyId TEXT)"];
    }];
}

+ (void)getModelWithKey:(NSString *)key value:(NSString *)value completionBlock:(void(^)(NSArray<ProvincesModel *> *models))block{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        
        NSString *sql = [NSString stringWithFormat:@"SELECT * FROM ProvincesModel WHERE %@ = %@",key,value];
        NSMutableArray *array = [NSMutableArray array];
        
        FMResultSet *resultSet = [database executeQuery:sql];
        if (resultSet) {
            while ([resultSet next]){
                ProvincesModel *model = [[ProvincesModel alloc] init];
                model.regionId = [resultSet stringForColumn:@"regionId"];
                model.regionName = [resultSet stringForColumn:@"regionName"];
                model.regionType = [resultSet stringForColumn:@"regionType"];
                model.parentId = [resultSet stringForColumn:@"parentId"];
                model.agencyId = [resultSet stringForColumn:@"agencyId"];
                [array addObject:model];
            }
            [resultSet close];
        }else{
            NSLog(@"Error ====== %@",database.lastError);
        }
        
       dispatch_async(dispatch_get_main_queue(), ^{
            block(array);
        });
    }];
}

+ (void)insertModel:(ProvincesModel *)model{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        BOOL result = [database executeUpdate:@"INSERT INTO ProvincesModel (regionId,regionName,regionType,parentId,agencyId) VALUES (? , ? , ? , ? , ?)",
        model.regionId,model.regionName,model.regionType,model.parentId,model.agencyId];
        if (!result) {
            NSLog(@"error ===== %@",database.lastError);
            NSLog(@"model ===== %@",model);
        }
    }];
}

+ (void)insertModels:(NSArray<ProvincesModel *> *)modelArray{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [modelArray enumerateObjectsUsingBlock:^(ProvincesModel * _Nonnull model, NSUInteger idx, BOOL * _Nonnull stop) {
            BOOL result = [database executeUpdate:@"INSERT INTO ProvincesModel (regionId,regionName,regionType,parentId,agencyId) VALUES (? , ? , ? , ? , ?)",
            model.regionId,model.regionName,model.regionType,model.parentId,model.agencyId];
            if (!result) {
                NSLog(@"error ===== %@",database.lastError);
                NSLog(@"model ===== %@",model);
            }
        }];
    }];
}

+ (void)replaceModel:(ProvincesModel *)model{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [database executeUpdate:@"REPLACE INTO ProvincesModel (regionId,regionName,regionType,parentId,agencyId) VALUES (? , ? , ? , ? , ?)",
         model.regionId,model.regionName,model.regionType,model.parentId,model.agencyId];
    }];
}

+ (void)replaceModels:(NSArray<ProvincesModel *> *)modelArray{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [ProvincesModel replaceModels:modelArray database:database];
    }];
}

+ (void)replaceModels:(NSArray<ProvincesModel *> *)modelArray database:(FMDatabase *)database{
    [modelArray enumerateObjectsUsingBlock:^(ProvincesModel * _Nonnull model, NSUInteger idx, BOOL * _Nonnull stop) {
        [database executeUpdate:@"REPLACE INTO ProvincesModel (regionId,regionName,regionType,parentId,agencyId) VALUES (? , ? , ? , ? , ?)",
         model.regionId,model.regionName,model.regionType,model.parentId,model.agencyId];
        
        if (model.childArray.count) {
            [ProvincesModel replaceModels:model.childArray database:database];
        }
        
    }];
}

/** 更新
*/
+ (void)updateModel:(ProvincesModel *)model{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        BOOL result = [database executeUpdate:@"UPDATE ProvincesModel SET regionName = ?,regionType = ?,parentId = ?,agencyId = ? WHERE regionId = ?" ,model.regionName,model.regionType,model.parentId,model.agencyId,model.regionId];
        if (!result) {
            NSLog(@"error ===== %@",database.lastError);
            NSLog(@"model ===== %@",model);
        }
    }];
}

+ (void)deleteModel:(ProvincesModel *)model{
    [DatabaseManagement databaseChildThreadInTransaction:^(FMDatabase *database, BOOL *rollback) {
        [database executeUpdate:@"DELETE FROM ProvincesModel WHERE regionId = ?",model.regionId];
    }];
}

@end
