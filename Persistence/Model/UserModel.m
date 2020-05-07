//
//  UserModel.m
//  FmdbDemo
//
//  Created by 苏沫离 on 2020/4/26.
//  Copyright © 2020 苏沫离. All rights reserved.
//

#import "UserModel.h"
#import <objc/message.h>

bool isEqualObject(id modelA,id modelB){
    if (modelA == modelB){
        return YES;//内存地址相同，一定相同
    }
    
    //两个实例不属于同一个类，没有必要进行下去
    if (![modelB isKindOfClass:object_getClass(modelA)] || !modelB || !modelA){
        return NO;
    }
    
    __block BOOL isSame = YES;
    unsigned int varCount = 0;
    Ivar *ivarList = class_copyIvarList(object_getClass(modelA), &varCount);
    for (int i = 0; i < varCount; i ++){
        Ivar ivar = ivarList[i];
        NSString *key = [NSString stringWithUTF8String:ivar_getName(ivar)];
        if ([modelA respondsToSelector:@selector(valueForKey:)] &&
            [modelB respondsToSelector:@selector(valueForKey:)]){
            id oldValue = [modelA valueForKey:key];
            id newValue = [modelB valueForKey:key];
            BOOL haveEqual = (!oldValue && !newValue) || [oldValue isEqual:newValue];
            if (haveEqual == NO){
                isSame = NO;
                break;
            }
        }
    }
    free(ivarList);
    return isSame;
}



NSString *const kUserInfoModelHeadPath = @"headPath";
NSString *const kUserInfoModelAge = @"age";
NSString *const kUserInfoModelSex = @"sex";
NSString *const kUserInfoModelNickName = @"nickName";
NSString *const kUserInfoModelNumberId = @"numberId";
NSString *const kUserInfoModelUserMobile = @"userMobile";
@interface UserInfoModel ()
- (id)objectOrNilForKey:(id)aKey fromDictionary:(NSDictionary *)dict;
@end

@implementation UserInfoModel

@synthesize headPath = _headPath;
@synthesize age = _age;
@synthesize sex = _sex;
@synthesize nickName = _nickName;
@synthesize numberId = _numberId;
@synthesize userMobile = _userMobile;

+ (instancetype)modelObjectWithDictionary:(NSDictionary *)dict{
    if (dict && [dict isKindOfClass:[NSDictionary class]] && dict.allKeys > 0){
        return [[self alloc] initWithDictionary:dict];
    }else{
        return nil;
    }
}

- (instancetype)initWithDictionary:(NSDictionary *)dict{
    self = [super init];
    if(self && [dict isKindOfClass:[NSDictionary class]]) {
        self.headPath = [self objectOrNilForKey:kUserInfoModelHeadPath fromDictionary:dict];
        self.age = [self objectOrNilForKey:kUserInfoModelAge fromDictionary:dict];
        self.sex = [self objectOrNilForKey:kUserInfoModelSex fromDictionary:dict];
        self.nickName = [self objectOrNilForKey:kUserInfoModelNickName fromDictionary:dict];
        self.numberId = [self objectOrNilForKey:kUserInfoModelNumberId fromDictionary:dict];
        self.userMobile = [self objectOrNilForKey:kUserInfoModelUserMobile fromDictionary:dict];
    }
    return self;
}

- (NSDictionary *)dictionaryRepresentation{
    NSMutableDictionary *mutableDict = [NSMutableDictionary dictionary];
    [mutableDict setValue:self.headPath forKey:kUserInfoModelHeadPath];
    [mutableDict setValue:self.age forKey:kUserInfoModelAge];
    [mutableDict setValue:self.sex forKey:kUserInfoModelSex];
    [mutableDict setValue:self.nickName forKey:kUserInfoModelNickName];
    [mutableDict setValue:self.numberId forKey:kUserInfoModelNumberId];
    [mutableDict setValue:self.userMobile forKey:kUserInfoModelUserMobile];
    return [NSDictionary dictionaryWithDictionary:mutableDict];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@", [self dictionaryRepresentation]];
}

#pragma mark - Helper Method
- (id)objectOrNilForKey:(id)aKey fromDictionary:(NSDictionary *)dict{
    id object = [dict objectForKey:aKey];
    return [object isEqual:[NSNull null]] ? nil : object;
}

- (BOOL)isEqual:(id)object{
    return isEqualObject(self, object);
}

#pragma mark - NSCoding Methods

- (id)initWithCoder:(NSCoder *)aDecoder{
    self = [super init];
    self.headPath = [aDecoder decodeObjectForKey:kUserInfoModelHeadPath];
    self.age = [aDecoder decodeObjectForKey:kUserInfoModelAge];
    self.sex = [aDecoder decodeObjectForKey:kUserInfoModelSex];
    self.nickName = [aDecoder decodeObjectForKey:kUserInfoModelNickName];
    self.numberId = [aDecoder decodeObjectForKey:kUserInfoModelNumberId];
    self.userMobile = [aDecoder decodeObjectForKey:kUserInfoModelUserMobile];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeObject:_headPath forKey:kUserInfoModelHeadPath];
    [aCoder encodeObject:_age forKey:kUserInfoModelAge];
    [aCoder encodeObject:_sex forKey:kUserInfoModelSex];
    [aCoder encodeObject:_nickName forKey:kUserInfoModelNickName];
    [aCoder encodeObject:_numberId forKey:kUserInfoModelNumberId];
    [aCoder encodeObject:_userMobile forKey:kUserInfoModelUserMobile];
}

- (id)copyWithZone:(NSZone *)zone{
    UserInfoModel *copy = [[UserInfoModel alloc] init];
    if (copy) {
        copy.headPath = [self.headPath copyWithZone:zone];
        copy.age = [self.age copyWithZone:zone];
        copy.sex = [self.sex copyWithZone:zone];
        copy.nickName = [self.nickName copyWithZone:zone];
        copy.numberId = [self.numberId copyWithZone:zone];
        copy.userMobile = [self.userMobile copyWithZone:zone];
    }
    return copy;
}

@end

















NSString *const kUserModelUserInfo = @"userInfo";
@interface UserModel ()
- (id)objectOrNilForKey:(id)aKey fromDictionary:(NSDictionary *)dict;
@end

@implementation UserModel
@synthesize userInfo = _userInfo;

+ (instancetype)modelObjectWithDictionary:(NSDictionary *)dict{
    if (dict && [dict isKindOfClass:[NSDictionary class]] && dict.allKeys > 0){
        return [[self alloc] initWithDictionary:dict];
    }else{
        return nil;
    }
}

- (instancetype)initWithDictionary:(NSDictionary *)dict{
    self = [super init];
    if(self && [dict isKindOfClass:[NSDictionary class]]) {
        self.userInfo = [UserInfoModel modelObjectWithDictionary:[dict objectForKey:kUserModelUserInfo]];
    }
    return self;
}

- (NSDictionary *)dictionaryRepresentation{
    NSMutableDictionary *mutableDict = [NSMutableDictionary dictionary];
    [mutableDict setValue:[self.userInfo dictionaryRepresentation] forKey:kUserModelUserInfo];
    return [NSDictionary dictionaryWithDictionary:mutableDict];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@", [self dictionaryRepresentation]];
}

#pragma mark - Helper Method
- (id)objectOrNilForKey:(id)aKey fromDictionary:(NSDictionary *)dict{
    id object = [dict objectForKey:aKey];
    return [object isEqual:[NSNull null]] ? nil : object;
}

- (BOOL)isEqual:(id)object{
    return isEqualObject(self, object);
}

#pragma mark - NSCoding Methods

- (id)initWithCoder:(NSCoder *)aDecoder{
    self = [super init];
    self.userInfo = [aDecoder decodeObjectForKey:kUserModelUserInfo];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeObject:_userInfo forKey:kUserModelUserInfo];
}

- (id)copyWithZone:(NSZone *)zone{
    UserModel *copy = [[UserModel alloc] init];
    if (copy) {
        copy.userInfo = [self.userInfo copyWithZone:zone];
    }
    return copy;
}

@end
