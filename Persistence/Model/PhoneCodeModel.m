//
//  PhoneCodeModel.m
//  Persistence
//
//  Created by 苏沫离 on 2020/4/29.
//  Copyright © 2020 苏沫离. All rights reserved.
//
#import "PhoneCodeModel.h"


NSString *const kPhoneCodeModelCountryCode = @"code";
NSString *const kPhoneCodeModelCountryPinYin = @"pinYin";
NSString *const kPhoneCodeModelCountryEnglish = @"english";
NSString *const kPhoneCodeModelPhoneCode = @"phoneCode";
NSString *const kPhoneCodeModelCountryChinese = @"chinese";


@interface PhoneCodeModel ()

- (id)objectOrNilForKey:(id)aKey fromDictionary:(NSDictionary *)dict;

@end

@implementation PhoneCodeModel

@synthesize countryCode = _countryCode;
@synthesize countryPinYin = _countryPinYin;
@synthesize countryEnglish = _countryEnglish;
@synthesize phoneCode = _phoneCode;
@synthesize countryChinese = _countryChinese;


+ (instancetype)modelObjectWithDictionary:(NSDictionary *)dict{
    return [[self alloc] initWithDictionary:dict];
}

- (instancetype)initWithDictionary:(NSDictionary *)dict{
    self = [super init];
    if(self && [dict isKindOfClass:[NSDictionary class]]) {
        self.countryCode = [self objectOrNilForKey:kPhoneCodeModelCountryCode fromDictionary:dict];
        self.countryPinYin = [self objectOrNilForKey:kPhoneCodeModelCountryPinYin fromDictionary:dict];
        self.countryEnglish = [self objectOrNilForKey:kPhoneCodeModelCountryEnglish fromDictionary:dict];
        self.phoneCode = [self objectOrNilForKey:kPhoneCodeModelPhoneCode fromDictionary:dict];
        self.countryChinese = [self objectOrNilForKey:kPhoneCodeModelCountryChinese fromDictionary:dict];
    }
    return self;
}

- (NSDictionary *)dictionaryRepresentation{
    NSMutableDictionary *mutableDict = [NSMutableDictionary dictionary];
    [mutableDict setValue:self.countryCode forKey:kPhoneCodeModelCountryCode];
    [mutableDict setValue:self.countryPinYin forKey:kPhoneCodeModelCountryPinYin];
    [mutableDict setValue:self.countryEnglish forKey:kPhoneCodeModelCountryEnglish];
    [mutableDict setValue:self.phoneCode forKey:kPhoneCodeModelPhoneCode];
    [mutableDict setValue:self.countryChinese forKey:kPhoneCodeModelCountryChinese];
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
    self.countryCode = [aDecoder decodeObjectForKey:kPhoneCodeModelCountryCode];
    self.countryPinYin = [aDecoder decodeObjectForKey:kPhoneCodeModelCountryPinYin];
    self.countryEnglish = [aDecoder decodeObjectForKey:kPhoneCodeModelCountryEnglish];
    self.phoneCode = [aDecoder decodeObjectForKey:kPhoneCodeModelPhoneCode];
    self.countryChinese = [aDecoder decodeObjectForKey:kPhoneCodeModelCountryChinese];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder{
    [aCoder encodeObject:_countryCode forKey:kPhoneCodeModelCountryCode];
    [aCoder encodeObject:_countryPinYin forKey:kPhoneCodeModelCountryPinYin];
    [aCoder encodeObject:_countryEnglish forKey:kPhoneCodeModelCountryEnglish];
    [aCoder encodeObject:_phoneCode forKey:kPhoneCodeModelPhoneCode];
    [aCoder encodeObject:_countryChinese forKey:kPhoneCodeModelCountryChinese];
}

- (id)copyWithZone:(NSZone *)zone{
    PhoneCodeModel *copy = [[PhoneCodeModel alloc] init];
    if (copy) {
        copy.countryCode = [self.countryCode copyWithZone:zone];
        copy.countryPinYin = [self.countryPinYin copyWithZone:zone];
        copy.countryEnglish = [self.countryEnglish copyWithZone:zone];
        copy.phoneCode = [self.phoneCode copyWithZone:zone];
        copy.countryChinese = [self.countryChinese copyWithZone:zone];
    }
    return copy;
}

@end


@implementation PhoneCodeModel (DemoData)

+ (PhoneCodeModel *)phoneChina{
    
    NSDictionary *dict = @{@"chinese":@"中国",
                           @"code":@"CN",
                           @"english":@"China",
                           @"phoneCode":@"+8676",
                           @"pinYin":@"zhong guo1",};
    PhoneCodeModel *model = [PhoneCodeModel modelObjectWithDictionary:dict];
    return model;
}


+ (NSMutableArray<PhoneCodeModel *> *)phoneCodeArray{
    NSMutableArray *phoneCodeArray = [NSMutableArray array];
    NSString *filePath = [[NSBundle bundleWithPath:[[NSBundle mainBundle] pathForResource:@"Resource" ofType:@"bundle"]] pathForResource:@"PhoneCode" ofType:@"json"];

    NSData *data = [NSData dataWithContentsOfFile:filePath];
    id json = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil];
    if (json && [json isKindOfClass:[NSArray class]]){
        NSArray<NSDictionary *> *array = (NSArray *)json;
        NSMutableArray<PhoneCodeModel *> *modelArray = [NSMutableArray arrayWithCapacity:array.count];
        [array enumerateObjectsUsingBlock:^(NSDictionary * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            PhoneCodeModel *model = [PhoneCodeModel modelObjectWithDictionary:obj];
            [modelArray addObject:model];
        }];
       phoneCodeArray = modelArray;
    }
    return phoneCodeArray;
}

@end
