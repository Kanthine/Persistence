//
//  TextViewController.m
//  Persistence
//
//  Created by 苏沫离 on 2020/5/6.
//  Copyright © 2020 苏沫离. All rights reserved.
//

#import "TextViewController.h"
#import "PhoneCodeModel+DAO.h"
#import "ProvincesModel+DAO.h"
#import "DatabaseManagement.h"

@interface TextViewController ()
@property (weak, nonatomic) IBOutlet UITextField *chineseTextField;
@property (weak, nonatomic) IBOutlet UITextField *codeTextField;
@property (weak, nonatomic) IBOutlet UITextField *englishTextField;
@property (weak, nonatomic) IBOutlet UITextField *phoneCodeTextField;
@property (weak, nonatomic) IBOutlet UITextField *pinYinTextField;

@end

@implementation TextViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    
    [DatabaseManagement info];
}

- (PhoneCodeModel *)phoneCodeModel{
    PhoneCodeModel *model = [[PhoneCodeModel alloc] init];
    model.phoneCode = self.phoneCodeTextField.text;
    model.countryCode = self.codeTextField.text;
    model.countryPinYin = self.pinYinTextField.text;
    model.countryEnglish = self.englishTextField.text;
    model.countryChinese = self.chineseTextField.text;
    return model;
}

- (IBAction)insertButtonClick:(UIButton *)sender {
    NSLog(@"%s",__func__);
//    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//        [[PhoneCodeModel phoneCodeArray] enumerateObjectsUsingBlock:^(PhoneCodeModel * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
//            [PhoneCodeModel insertModel:obj];
//        }];
//    });
    
    [ProvincesModel replaceModels:[ProvincesModel provincesModelArray]];
    
    [PhoneCodeModel insertModel:self.phoneCodeModel];
}

- (IBAction)replaceButtonClick:(UIButton *)sender {
    NSLog(@"%s",__func__);
    [PhoneCodeModel replaceModel:self.phoneCodeModel];
}


- (IBAction)updateButtonClick:(UIButton *)sender {
    NSLog(@"%s",__func__);
    [PhoneCodeModel updateModel:self.phoneCodeModel];
}


- (IBAction)queueButtonClick:(UIButton *)sender {
    NSLog(@"%s",__func__);
//    PhoneCodeModel getModelWithKey:<#(nonnull NSString *)#> value:<#(nonnull NSString *)#> completionBlock:<#^(NSArray<PhoneCodeModel *> * _Nonnull models)block#>
//    + (void)getModelWithKey:(NSString *)key value:(NSString *)value completionBlock:(void(^)(NSArray<PhoneCodeModel *> *models))block;
}


- (IBAction)deleteButtonClick:(UIButton *)sender {
    NSLog(@"%s",__func__);
    [PhoneCodeModel deleteModel:self.phoneCodeModel];
}

- (IBAction)dropButtonClick:(UIButton *)sender {
    NSLog(@"%s",__func__);
    [PhoneCodeModel dropTable];
}


@end
