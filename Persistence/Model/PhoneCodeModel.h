//
//  PhoneCodeModel.h
//  Persistence
//
//  Created by 苏沫离 on 2020/4/29.
//  Copyright © 2020 苏沫离. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface PhoneCodeModel : NSObject <NSCoding, NSCopying>

@property (nonatomic, strong) NSString *countryCode;
@property (nonatomic, strong) NSString *countryPinYin;
@property (nonatomic, strong) NSString *countryEnglish;
@property (nonatomic, strong) NSString *phoneCode;
@property (nonatomic, strong) NSString *countryChinese;

+ (instancetype)modelObjectWithDictionary:(NSDictionary *)dict;
- (instancetype)initWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)dictionaryRepresentation;

@end


@interface PhoneCodeModel (DemoData)

+ (PhoneCodeModel *)phoneChina;

+ (NSMutableArray<PhoneCodeModel *> *)phoneCodeArray;

@end
