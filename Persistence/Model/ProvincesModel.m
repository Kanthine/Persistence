//
//  ProvincesModel.m
//  Persistence
//
//  Created by 苏沫离 on 2020/4/29.
//  Copyright © 2020 苏沫离. All rights reserved.
//

#import "ProvincesModel.h"

NSString *const kProvincesModelParentId = @"parent_id";
NSString *const kProvincesModelAgencyId = @"agency_id";
NSString *const kProvincesModelRegionId = @"region_id";
NSString *const kProvincesModelRegionType = @"region_type";
NSString *const kProvincesModelChildArray = @"childArray";
NSString *const kProvincesModelRegionName = @"region_name";

@interface ProvincesModel ()

- (id)objectOrNilForKey:(id)aKey fromDictionary:(NSDictionary *)dict;

@end

@implementation ProvincesModel

@synthesize parentId = _parentId;
@synthesize agencyId = _agencyId;
@synthesize regionId = _regionId;
@synthesize regionType = _regionType;
@synthesize childArray = _childArray;
@synthesize regionName = _regionName;


+ (instancetype)modelObjectWithDictionary:(NSDictionary *)dict{
    return [[self alloc] initWithDictionary:dict];
}

- (instancetype)initWithDictionary:(NSDictionary *)dict{
    self = [super init];
    
    // This check serves to make sure that a non-NSDictionary object
    // passed into the model class doesn't break the parsing.
    if(self && [dict isKindOfClass:[NSDictionary class]]) {
        self.parentId = [self objectOrNilForKey:kProvincesModelParentId fromDictionary:dict];
        self.agencyId = [self objectOrNilForKey:kProvincesModelAgencyId fromDictionary:dict];
        self.regionId = [self objectOrNilForKey:kProvincesModelRegionId fromDictionary:dict];
        self.regionType = [self objectOrNilForKey:kProvincesModelRegionType fromDictionary:dict];
        NSObject *receivedChildArray = [dict objectForKey:kProvincesModelChildArray];
        NSMutableArray *parsedChildArray = [NSMutableArray array];
        if ([receivedChildArray isKindOfClass:[NSArray class]]) {
            for (NSDictionary *item in (NSArray *)receivedChildArray) {
                if ([item isKindOfClass:[NSDictionary class]]) {
                    [parsedChildArray addObject:[ProvincesModel modelObjectWithDictionary:item]];
                }
            }
        } else if ([receivedChildArray isKindOfClass:[NSDictionary class]]) {
            [parsedChildArray addObject:[ProvincesModel modelObjectWithDictionary:(NSDictionary *)receivedChildArray]];
        }
        self.childArray = [NSArray arrayWithArray:parsedChildArray];
        self.regionName = [self objectOrNilForKey:kProvincesModelRegionName fromDictionary:dict];
    }
    return self;
}

- (NSDictionary *)dictionaryRepresentation{
    NSMutableDictionary *mutableDict = [NSMutableDictionary dictionary];
    [mutableDict setValue:self.parentId forKey:kProvincesModelParentId];
    [mutableDict setValue:self.agencyId forKey:kProvincesModelAgencyId];
    [mutableDict setValue:self.regionId forKey:kProvincesModelRegionId];
    [mutableDict setValue:self.regionType forKey:kProvincesModelRegionType];
    NSMutableArray *tempArrayForChildArray = [NSMutableArray array];
    for (NSObject *subArrayObject in self.childArray) {
        if([subArrayObject respondsToSelector:@selector(dictionaryRepresentation)]) {
            // This class is a model object
            [tempArrayForChildArray addObject:[subArrayObject performSelector:@selector(dictionaryRepresentation)]];
        } else {
            // Generic object
            [tempArrayForChildArray addObject:subArrayObject];
        }
    }
    [mutableDict setValue:[NSArray arrayWithArray:tempArrayForChildArray] forKey:kProvincesModelChildArray];
    [mutableDict setValue:self.regionName forKey:kProvincesModelRegionName];
    return [NSDictionary dictionaryWithDictionary:mutableDict];
}

- (NSString *)description{
    return [NSString stringWithFormat:@"%@", [self dictionaryRepresentation]];
}

#pragma mark - Helper Method
- (id)objectOrNilForKey:(id)aKey fromDictionary:(NSDictionary *)dict{
    id object = [dict objectForKey:aKey];
    return [object isEqual:[NSNull null]] ? nil : object;
}


#pragma mark - NSCoding Methods

- (id)initWithCoder:(NSCoder *)aDecoder{
    self = [super init];
    self.parentId = [aDecoder decodeObjectForKey:kProvincesModelParentId];
    self.agencyId = [aDecoder decodeObjectForKey:kProvincesModelAgencyId];
    self.regionId = [aDecoder decodeObjectForKey:kProvincesModelRegionId];
    self.regionType = [aDecoder decodeObjectForKey:kProvincesModelRegionType];
    self.childArray = [aDecoder decodeObjectForKey:kProvincesModelChildArray];
    self.regionName = [aDecoder decodeObjectForKey:kProvincesModelRegionName];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeObject:_parentId forKey:kProvincesModelParentId];
    [aCoder encodeObject:_agencyId forKey:kProvincesModelAgencyId];
    [aCoder encodeObject:_regionId forKey:kProvincesModelRegionId];
    [aCoder encodeObject:_regionType forKey:kProvincesModelRegionType];
    [aCoder encodeObject:_childArray forKey:kProvincesModelChildArray];
    [aCoder encodeObject:_regionName forKey:kProvincesModelRegionName];
}

- (id)copyWithZone:(NSZone *)zone{
    ProvincesModel *copy = [[ProvincesModel alloc] init];
    if (copy) {
        copy.parentId = [self.parentId copyWithZone:zone];
        copy.agencyId = [self.agencyId copyWithZone:zone];
        copy.regionId = [self.regionId copyWithZone:zone];
        copy.regionType = [self.regionType copyWithZone:zone];
        copy.childArray = [self.childArray copyWithZone:zone];
        copy.regionName = [self.regionName copyWithZone:zone];
    }
    return copy;
}

@end


@implementation ProvincesModel (DemoData)

+ (NSMutableArray<ProvincesModel *> *)provincesModelArray{
    NSMutableArray *provincesModelArray = [NSMutableArray array];
    NSString *filePath = [[NSBundle bundleWithPath:[[NSBundle mainBundle] pathForResource:@"Resource" ofType:@"bundle"]] pathForResource:@"CityModelList" ofType:@"json"];

    NSData *data = [NSData dataWithContentsOfFile:filePath];
    id json = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil];
    if (json && [json isKindOfClass:[NSArray class]]){
        NSArray<NSDictionary *> *array = (NSArray *)json;
        NSMutableArray<ProvincesModel *> *modelArray = [NSMutableArray arrayWithCapacity:array.count];
        [array enumerateObjectsUsingBlock:^(NSDictionary * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            ProvincesModel *model = [ProvincesModel modelObjectWithDictionary:obj];
            [modelArray addObject:model];
        }];
       provincesModelArray = modelArray;
    }
    return provincesModelArray;
}

@end
