//
//  UserModel.h
//  FmdbDemo
//
//  Created by 苏沫离 on 2020/4/26.
//  Copyright © 2020 苏沫离. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UserInfoModel : NSObject <NSCoding, NSCopying>

@property (nonatomic, strong) NSString *headPath;
@property (nonatomic, strong) NSString *age;
@property (nonatomic, strong) NSString *sex;
@property (nonatomic, strong) NSString *nickName;
@property (nonatomic, strong) NSString *numberId;
@property (nonatomic, strong) NSString *userMobile;

+ (instancetype)modelObjectWithDictionary:(NSDictionary *)dict;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;

@end


@interface UserModel : NSObject <NSCoding, NSCopying>

@property (nonatomic, strong) UserInfoModel *userInfo;

+ (instancetype)modelObjectWithDictionary:(NSDictionary *)dict;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;

@end


NS_ASSUME_NONNULL_END
