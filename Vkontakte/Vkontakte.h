/*
 * Copyright 2011 Andrey Yastrebov
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import <Foundation/Foundation.h>
#import "VkontakteViewController.h"

extern NSString * const vkAppId;
extern NSString * const vkPermissions;
extern NSString * const vkRedirectUrl;


@protocol VkUserInfo

//@property (strong, nonatomic) NSString * bdate;
//@property (strong, nonatomic) NSString * first_name;
//@property (strong, nonatomic) NSString * last_name;
//@property (strong, nonatomic) NSString * photo;
//@property (strong, nonatomic) NSString * photo_big;
//@property (strong, nonatomic) NSNumber * sex;
//@property (strong, nonatomic) NSString * email;
//@property (strong, nonatomic) NSNumber * uid;

@end


@protocol VkontakteDelegate;

@interface Vkontakte : NSObject <VkontakteViewControllerDelegate, UIAlertViewDelegate>
{    

    NSString *accessToken;
    NSDate *expirationDate;
    NSString *userId;
    NSString *email;

    BOOL _isCaptcha;
}

@property (nonatomic, weak) id <VkontakteDelegate> delegate;

+ (id)sharedInstance;
- (BOOL)isAuthorized;
- (void)authenticateBaseViewController:(UIViewController *)baseViewController
                               success:(void (^)())success
                               failure:(void (^)(NSError *))failure
                                cancel:(void (^)())cancel;

- (void)logout;
- (void)getUserInfo;
- (void)postMessageToWall:(NSString *)message;
- (void)postMessageToWall:(NSString *)message link:(NSURL *)url;
- (void)postImageToWall:(UIImage *)image;
- (void)postImageToWall:(UIImage *)image text:(NSString *)message;
- (void)postImageToWall:(UIImage *)image text:(NSString *)message link:(NSURL *)url;

@end

@protocol VkontakteDelegate <NSObject>
@required
- (void)vkontakteDidFailedWithError:(NSError *)error;
- (void)showVkontakteAuthController:(UIViewController *)controller;
- (void)vkontakteAuthControllerDidCancelled;
@optional
- (void)vkontakteDidFinishLogin:(Vkontakte *)vkontakte;
- (void)vkontakteDidFinishLogOut:(Vkontakte *)vkontakte;

- (void)vkontakteDidFinishGettinUserInfo:(NSDictionary<VkUserInfo> *)info;
- (void)vkontakteDidFinishPostingToWall:(NSDictionary *)responce;

@end
