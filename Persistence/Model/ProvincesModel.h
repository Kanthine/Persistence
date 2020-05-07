//
//  ProvincesModel.h
//  Persistence
//
//  Created by 苏沫离 on 2020/4/29.
//  Copyright © 2020 苏沫离. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** 省市区数据模型类
 */
@interface ProvincesModel : NSObject <NSCoding, NSCopying>

@property (nonatomic, strong) NSString *agencyId;//国家 ID
@property (nonatomic, strong) NSString *parentId;//上一级的地区ID
@property (nonatomic, strong) NSString *regionName;//地区名字
@property (nonatomic, strong) NSString *regionId;//地区ID
@property (nonatomic, strong) NSString *regionType;//地区层级
@property (nonatomic, strong) NSArray<ProvincesModel *> *childArray;


+ (instancetype)modelObjectWithDictionary:(NSDictionary *)dict;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;

@end


@interface ProvincesModel (DemoData)

+ (NSMutableArray<ProvincesModel *> *)provincesModelArray;

@end


NS_ASSUME_NONNULL_END
