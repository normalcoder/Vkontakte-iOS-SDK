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

#import "Vkontakte.h"

static NSString * kVKCode = @"VKCode";

@interface Vkontakte (Private)

- (void)storeSession;
- (BOOL)isSessionValid;
- (void)getCaptcha;
- (NSDictionary *)sendRequest:(NSString *)reqURl withCaptcha:(BOOL)captcha;
- (NSDictionary *)sendPOSTRequest:(NSString *)reqURl withImageData:(NSData *)imageData;
- (NSString *)URLEncodedString:(NSString *)str;
@end

@implementation Vkontakte (Private)

- (void)storeSession
{
    // Save authorization information
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:accessToken forKey:@"VKAccessTokenKey"];
    [defaults setObject:expirationDate forKey:@"VKExpirationDateKey"];
    [defaults setObject:userId forKey:@"VKUserID"];
    [defaults setObject:email forKey:@"VKUserEmail"];
    [defaults synchronize];
}

- (BOOL)isSessionValid 
{
    return (accessToken != nil && expirationDate != nil && userId != nil
            && NSOrderedDescending == [expirationDate compare:[NSDate date]]);
}

- (void)getCaptcha 
{
    NSString *captcha_img = [[NSUserDefaults standardUserDefaults] objectForKey:@"captcha_img"];
    UIAlertView *myAlertView = [[UIAlertView alloc] initWithTitle:@"Введите код:\n\n\n\n\n"
                                                          message:@"\n" delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"OK", nil];
    
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(12.0, 45.0, 130.0, 50.0)];
    imageView.image = [UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:captcha_img]]];
    [myAlertView addSubview:imageView];
    
    UITextField *myTextField = [[UITextField alloc] initWithFrame:CGRectMake(12.0, 110.0, 260.0, 25.0)];
    [myTextField setBackgroundColor:[UIColor whiteColor]];
    
    myTextField.autocorrectionType = UITextAutocorrectionTypeNo;
    myTextField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    myTextField.tag = 33;
    
    [myAlertView addSubview:myTextField];
    [myAlertView show];
}

- (void)alertView:(UIAlertView *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if(_isCaptcha && buttonIndex == 1)
    {
        _isCaptcha = NO;
        
        UITextField *myTextField = (UITextField *)[actionSheet viewWithTag:33];
        [[NSUserDefaults standardUserDefaults] setObject:myTextField.text forKey:@"captcha_user"];
        NSLog(@"Captcha entered: %@",myTextField.text);
        
        // Вспоминаем какой был последний запрос и делаем его еще раз
        NSString *request = [[NSUserDefaults standardUserDefaults] objectForKey:@"request"];
        
        NSDictionary *newRequestDict =[self sendRequest:request withCaptcha:YES];
        NSString *errorMsg = [[newRequestDict  objectForKey:@"error"] objectForKey:@"error_msg"];
        if(errorMsg) 
        {
            NSError *error = [NSError errorWithDomain:@"vk.com" 
                                                 code:[[[newRequestDict  objectForKey:@"error"] objectForKey:@"error_code"] intValue] 
                                             userInfo:[newRequestDict  objectForKey:@"error"]];
            if (self.delegate && [self.delegate respondsToSelector:@selector(vkontakteDidFailedWithError:)]) 
            {
                [self.delegate vkontakteDidFailedWithError:error];
            }
            
        } 
        else 
        {
            if (self.delegate && [self.delegate respondsToSelector:@selector(vkontakteDidFinishPostingToWall:)]) 
            {
                [self.delegate vkontakteDidFinishPostingToWall:newRequestDict];
            }
            
        }
    }
}

- (NSDictionary *)sendRequest:(NSString *)reqURl withCaptcha:(BOOL)captcha 
{
    if(captcha == YES)
    {
        NSString *captcha_sid = [[NSUserDefaults standardUserDefaults] objectForKey:@"captcha_sid"];
        NSString *captcha_user = [[NSUserDefaults standardUserDefaults] objectForKey:@"captcha_user"];
        reqURl = [reqURl stringByAppendingFormat:@"&captcha_sid=%@&captcha_key=%@", captcha_sid, [self URLEncodedString: captcha_user]];
    }
    NSLog(@"Sending request: %@", reqURl);
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:reqURl] 
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData 
                                                       timeoutInterval:60.0]; 
    
    NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:nil];
    
    if(responseData)
    {        
        NSError* error;
        NSDictionary* dict = [NSJSONSerialization 
                              JSONObjectWithData:responseData                              
                              options:kNilOptions 
                              error:&error];
        
        NSString *errorMsg = [[dict objectForKey:@"error"] objectForKey:@"error_msg"];
        
        NSLog(@"Server response: %@ \nError: %@", dict, errorMsg);
        
        if([errorMsg isEqualToString:@"Captcha needed"])
        {
            _isCaptcha = YES;
            NSString *captcha_sid = [[dict objectForKey:@"error"] objectForKey:@"captcha_sid"];
            NSString *captcha_img = [[dict objectForKey:@"error"] objectForKey:@"captcha_img"];
            [[NSUserDefaults standardUserDefaults] setObject:captcha_img forKey:@"captcha_img"];
            [[NSUserDefaults standardUserDefaults] setObject:captcha_sid forKey:@"captcha_sid"];
            [[NSUserDefaults standardUserDefaults] setObject:reqURl forKey:@"request"];
            [[NSUserDefaults standardUserDefaults] synchronize];
            
            [self getCaptcha];
        }
        
        return dict;
    }
    return nil;
}

- (NSDictionary *)sendPOSTRequest:(NSString *)reqURl withImageData:(NSData *)imageData 
{
    NSLog(@"Sending request: %@", reqURl);
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:reqURl] 
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData 
                                                       timeoutInterval:60.0]; 
    [request setHTTPMethod:@"POST"]; 
    
    [request addValue:@"8bit" forHTTPHeaderField:@"Content-Transfer-Encoding"];
    
    CFUUIDRef uuid = CFUUIDCreate(nil);
    NSString *uuidString = (__bridge_transfer NSString*)CFUUIDCreateString(nil, uuid);
    CFRelease(uuid);
    NSString *stringBoundary = [NSString stringWithFormat:@"0xKhTmLbOuNdArY-%@",uuidString];
    NSString *endItemBoundary = [NSString stringWithFormat:@"\r\n--%@\r\n",stringBoundary];
    
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data;  boundary=%@", stringBoundary];
    
    [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
    
    NSMutableData *body = [NSMutableData data];
    
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n",stringBoundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: image/jpg\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:imageData];        
    [body appendData:[[NSString stringWithFormat:@"%@",endItemBoundary] dataUsingEncoding:NSUTF8StringEncoding]];
    
    [request setHTTPBody:body];
    
    NSData *responseData = [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:nil];
   
    if(responseData)
    {        
        NSError* error;
        NSDictionary* dict = [NSJSONSerialization 
                              JSONObjectWithData:responseData
                              options:kNilOptions 
                              error:&error];
        
        NSString *errorMsg = [[dict objectForKey:@"error"] objectForKey:@"error_msg"];
        
        NSLog(@"Server response: %@ \nError: %@", dict, errorMsg);
        
        return dict;
    }
    return nil;
}

- (NSString *)URLEncodedString:(NSString *)str
{
    NSString *result = (__bridge_transfer NSString *)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                                           (__bridge CFStringRef)str,
                                                                           NULL,
																		   CFSTR("!*'();:@&=+$,/?%#[]"),
                                                                           kCFStringEncodingUTF8);
	return result;
}

@end

@implementation Vkontakte

NSString * const vkAppId = @"3276219"; // Wisdom
NSString * const vkPermissions = @""; //@"wall,photos,offline"; // TODO: add the necessary permissions
NSString * const vkRedirectUrl = @"http://oauth.vk.com/blank.html";

@synthesize delegate;

#pragma mark - Initialize

+ (id)sharedInstance
{
    static dispatch_once_t pred = 0;
    __strong static id _sharedObject = nil;
    dispatch_once(&pred, ^{
        _sharedObject = [[self alloc] init]; // or some other init method
    });
    return _sharedObject;
}

- (id)init
{
    self = [super init];
    if (self) 
    {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        accessToken = [defaults objectForKey:@"VKAccessTokenKey"];
        expirationDate = [defaults objectForKey:@"VKExpirationDateKey"];
        userId = [defaults objectForKey:@"VKUserID"];
        email = [defaults objectForKey:@"VKUserEmail"];
    }
    return self;
}

- (void)storeCode:(NSString *)code {
    [[NSUserDefaults standardUserDefaults] setObject:code forKey:kVKCode];
}

- (NSString *)storedCode {
    return [[NSUserDefaults standardUserDefaults] objectForKey:kVKCode];
}

- (BOOL)isAuthorized
{    
    if (![self isSessionValid]) 
    {
        return NO;
    } 
    else 
    {
        return YES;
    }
}

- (void)authenticateBaseViewController:(UIViewController *)baseViewController
                               success:(void (^)(NSString * code))success
                               failure:(void (^)(NSError *))failure
                                cancel:(void (^)())cancel {
    [self clearCookies];
    
    /*
     WARNING: auth_type was set to "token" here.
     This quick patch allows us to use VK's code auth mechanism instead of getting an access token right here.
     It means that the other VK functions in this lib are now broken.
     To fix this, we need to request our own access_token using the code we've just received.
     */
    NSString *authLink = [NSString stringWithFormat:@"http://oauth.vk.com/oauth/authorize?client_id=%@&scope=%@&redirect_uri=%@&display=touch&response_type=code", vkAppId, vkPermissions, vkRedirectUrl];
    NSURL *url = [NSURL URLWithString:authLink];
    
    VkontakteViewController *vkontakteViewController =
    [[VkontakteViewController alloc]
     initWithAuthLink:url
     baseViewController:baseViewController
     success:^(NSString * code){
         [self storeCode:code];
         success(code);
     } failure:^(NSError * e) {
         failure(e);
     } cancel:^{
         cancel();
     }];
    vkontakteViewController.delegate = self;
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:vkontakteViewController];
    
    [baseViewController presentViewController:navController
                                     animated:YES
                                   completion:
     ^{}];
}

- (void)logout {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
        [self _logout];
    });
}

- (void)clearCookies {
    NSHTTPCookieStorage * cookies = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    NSArray * cookiesUrlStrings =
    @[@"http://api.vk.com"
    , @"http://vk.com"
    , @"http://login.vk.com"
    , @"http://oauth.vk.com"
    
    , @"https://api.vk.com"
    , @"https://vk.com"
    , @"https://login.vk.com"
    , @"https://oauth.vk.com"
    ];
    
    for (NSString * string in cookiesUrlStrings) {
        NSArray * vkCookies = [cookies cookiesForURL:[NSURL URLWithString:string]];
        for (NSHTTPCookie * cookie in vkCookies) {
            [cookies deleteCookie:cookie];
        }
    }
}

- (void)_logout
{
    NSString *logout = [NSString stringWithFormat:@"http://api.vk.com/oauth/logout?client_id=%@", vkAppId];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:logout] 
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData 
                                                       timeoutInterval:60.0]; 
    NSData *responseData = [NSURLConnection sendSynchronousRequest:request 
                                                 returningResponse:nil 
                                                             error:nil];
    if(responseData)
    {
        NSError* error;
        NSDictionary* dict = [NSJSONSerialization 
                              JSONObjectWithData:responseData
                              options:kNilOptions 
                              error:&error];
        NSLog(@"Logout: %@", dict);
        
        
        [self clearCookies];
        
        // Remove saved authorization information if it exists and it is
        // ok to clear it (logout, session invalid, app unauthorized)
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if ([defaults objectForKey:@"VKAccessTokenKey"]) 
        {
            [defaults removeObjectForKey:@"VKAccessTokenKey"];
            [defaults removeObjectForKey:@"VKExpirationDateKey"];
            [defaults removeObjectForKey:@"VKUserID"];
            [defaults removeObjectForKey:@"VKUserEmail"];
            [defaults synchronize];
            
            // Nil out the session variables to prevent
            // the app from thinking there is a valid session
            if (accessToken) 
            {
                accessToken = nil;
            }
            if (expirationDate) 
            {
                expirationDate = nil;
            }
        }
        
        if (self.delegate && [self.delegate respondsToSelector:@selector(vkontakteDidFinishLogOut:)]) 
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate vkontakteDidFinishLogOut:self];
            });
        }
    }
}

- (void)getUserInfo {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
        [self _getUserInfo];
    });
}

- (void)_getUserInfo
{    
    if (![self isAuthorized]) return;
    
    NSMutableString *requestString = [[NSMutableString alloc] init];
	[requestString appendFormat:@"%@/", @"https://api.vk.com/method"];
    [requestString appendFormat:@"%@?", @"getProfiles"];
    [requestString appendFormat:@"uid=%@&", userId];
    NSMutableString *fields = [[NSMutableString alloc] init];
    [fields appendString:@"sex,bdate,photo,photo_big"];
    [requestString appendFormat:@"fields=%@&", fields];
    [requestString appendFormat:@"access_token=%@", accessToken];
    
	NSURL *url = [NSURL URLWithString:requestString];
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
	
	NSData *response = [NSURLConnection sendSynchronousRequest:request 
											 returningResponse:nil 
														 error:nil];
	NSString *responseString = [[NSString alloc] initWithData:response 
                                                     encoding:NSUTF8StringEncoding];
	NSLog(@"%@",responseString);
    
    NSError* error;
    NSDictionary<VkUserInfo> * parsedDictionary =
    [NSJSONSerialization
     JSONObjectWithData:response
     options:kNilOptions
     error:&error];
    
    NSArray *array = [parsedDictionary objectForKey:@"response"];
    
    if ([parsedDictionary objectForKey:@"response"])
    {
        parsedDictionary = [array objectAtIndex:0];
        parsedDictionary = [NSMutableDictionary dictionaryWithDictionary:parsedDictionary];
        [parsedDictionary setValue:email forKey:@"email"];
        
        if ([self.delegate respondsToSelector:@selector(vkontakteDidFinishGettinUserInfo:)])
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate vkontakteDidFinishGettinUserInfo:parsedDictionary];
            });
        }
    }
    else
    {        
        NSDictionary *errorDict = [parsedDictionary objectForKey:@"error"];
        
        if ([self.delegate respondsToSelector:@selector(vkontakteDidFailedWithError:)])
        {
            NSError *error = [NSError errorWithDomain:@"http://api.vk.com/method" 
                                                 code:[[errorDict objectForKey:@"error_code"] intValue]
                                             userInfo:errorDict];
            
            if (error.code == 5) 
            {
                [self _logout];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate vkontakteDidFailedWithError:error];
            });
        }
    }
}

- (void)postMessageToWall:(NSString *)message
{
    if (![self isAuthorized]) return;
            
    NSString *sendTextMessage = [NSString stringWithFormat:@"https://api.vk.com/method/wall.post?owner_id=%@&access_token=%@&message=%@", 
                                 userId, 
                                 accessToken, 
                                 [self URLEncodedString:message]];
    NSLog(@"sendTextMessage: %@", sendTextMessage);
    
    NSDictionary *result = [self sendRequest:sendTextMessage withCaptcha:NO];
    // Если есть описание ошибки в ответе
    NSString *errorMsg = [[result objectForKey:@"error"] objectForKey:@"error_msg"];
    if(errorMsg) 
    {
        NSDictionary *errorDict = [result objectForKey:@"error"];
        
        if ([self.delegate respondsToSelector:@selector(vkontakteDidFailedWithError:)])
        {
            NSError *error = [NSError errorWithDomain:@"http://api.vk.com/method" 
                                                 code:[[errorDict objectForKey:@"error_code"] intValue]
                                             userInfo:errorDict];
            
            if (error.code == 5) 
            {
                [self _logout];
            }
            
            [self.delegate vkontakteDidFailedWithError:error];
        }
    } 
    else 
    {
        if (self.delegate && [self.delegate respondsToSelector:@selector(vkontakteDidFinishPostingToWall:)]) 
        {
            [self.delegate vkontakteDidFinishPostingToWall:result];
        }
    }
}

- (void)postMessageToWall:(NSString *)message link:(NSURL *)url
{
    if (![self isAuthorized]) return;
    
    NSString *link = [url absoluteString];
    
    NSString *sendTextAndLinkMessage = [NSString stringWithFormat:@"https://api.vk.com/method/wall.post?owner_id=%@&access_token=%@&message=%@&attachment=%@", 
                                        userId, 
                                        accessToken, 
                                        [self URLEncodedString:message], 
                                        link];
    
    NSLog(@"sendTextAndLinkMessage: %@", sendTextAndLinkMessage);
    
    // Если запрос более сложный мы можем работать дальше с полученным ответом
    NSDictionary *result = [self sendRequest:sendTextAndLinkMessage withCaptcha:NO];
    NSString *errorMsg = [[result objectForKey:@"error"] objectForKey:@"error_msg"];
    if(errorMsg) 
    {
        NSDictionary *errorDict = [result objectForKey:@"error"];
        
        if ([self.delegate respondsToSelector:@selector(vkontakteDidFailedWithError:)])
        {
            NSError *error = [NSError errorWithDomain:@"http://api.vk.com/method" 
                                                 code:[[errorDict objectForKey:@"error_code"] intValue]
                                             userInfo:errorDict];
            
            if (error.code == 5) 
            {
                [self _logout];
            }
            
            [self.delegate vkontakteDidFailedWithError:error];
        }
    } 
    else 
    {
        if (self.delegate && [self.delegate respondsToSelector:@selector(vkontakteDidFinishPostingToWall:)]) 
        {
            [self.delegate vkontakteDidFinishPostingToWall:result];
        }
    }
}

- (void)postImageToWall:(UIImage *)image text:(NSString *)message link:(NSURL *)url
{
    if (![self isAuthorized]) return;
    
    NSString *getWallUploadServer = [NSString stringWithFormat:@"https://api.vk.com/method/photos.getWallUploadServer?owner_id=%@&access_token=%@", userId, accessToken];
    
    NSDictionary *uploadServer = [self sendRequest:getWallUploadServer withCaptcha:NO];
    
    NSString *upload_url = [[uploadServer objectForKey:@"response"] objectForKey:@"upload_url"];
    
    NSData *imageData = UIImageJPEGRepresentation(image, 1.0f);
    
    NSDictionary *postDictionary = [self sendPOSTRequest:upload_url withImageData:imageData];
    
    NSString *hash = [postDictionary objectForKey:@"hash"];
    NSString *photo = [postDictionary objectForKey:@"photo"];
    NSString *server = [postDictionary objectForKey:@"server"];
    
    NSString *saveWallPhoto = [NSString stringWithFormat:@"https://api.vk.com/method/photos.saveWallPhoto?owner_id=%@&access_token=%@&server=%@&photo=%@&hash=%@", 
                               userId, 
                               accessToken,
                               server,
                               photo,
                               hash];
    
    saveWallPhoto = [saveWallPhoto stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    
    NSDictionary *saveWallPhotoDict = [self sendRequest:saveWallPhoto withCaptcha:NO];
    
    NSDictionary *photoDict = [[saveWallPhotoDict objectForKey:@"response"] lastObject];
    NSString *photoId = [photoDict objectForKey:@"id"];
    
    NSString *postToWallLink;
    
    if (url) 
    {
        postToWallLink = [NSString stringWithFormat:@"https://api.vk.com/method/wall.post?owner_id=%@&access_token=%@&message=%@&attachments=%@,%@", 
                          userId, 
                          accessToken, 
                          [self URLEncodedString:message], 
                          photoId,
                          [url absoluteURL]];
    } 
    else 
    {
        postToWallLink = [NSString stringWithFormat:@"https://api.vk.com/method/wall.post?owner_id=%@&access_token=%@&message=%@&attachment=%@", 
                          userId, 
                          accessToken, 
                          [self URLEncodedString:message], 
                          photoId];
    }
    
    NSDictionary *postToWallDict = [self sendRequest:postToWallLink withCaptcha:NO];
    NSString *errorMsg = [[postToWallDict  objectForKey:@"error"] objectForKey:@"error_msg"];
    if(errorMsg) 
    {
        NSDictionary *errorDict = [postToWallDict objectForKey:@"error"];
        
        if ([self.delegate respondsToSelector:@selector(vkontakteDidFailedWithError:)])
        {
            NSError *error = [NSError errorWithDomain:@"http://api.vk.com/method" 
                                                 code:[[errorDict objectForKey:@"error_code"] intValue]
                                             userInfo:errorDict];
            
            if (error.code == 5) 
            {
                [self _logout];
            }
            
            [self.delegate vkontakteDidFailedWithError:error];
        }
    } 
    else 
    {
        if (self.delegate && [self.delegate respondsToSelector:@selector(vkontakteDidFinishPostingToWall:)]) 
        {
            [self.delegate vkontakteDidFinishPostingToWall:postToWallDict];
        }
    }
}

- (void)postImageToWall:(UIImage *)image
{   
    [self postImageToWall:image text:@""];
}

- (void)postImageToWall:(UIImage *)image text:(NSString *)message
{
    [self postImageToWall:image text:message link:nil];
}

#pragma mark - VkontakteViewControllerDelegate

- (void)authorizationDidSucceedWithToke:(NSString *)_accessToken 
                                 userId:(NSString *)_userId 
                                expDate:(NSDate *)_expDate
                              userEmail:(NSString *)_email

{
    accessToken = _accessToken;
    userId = _userId;
    expirationDate = _expDate;
    email = _email;
    
    [self storeSession];
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(vkontakteDidFinishLogin:)]) 
    {
        [self.delegate vkontakteDidFinishLogin:self];
    }
}

- (void)authorizationDidFailedWithError:(NSError *)error
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(vkontakteDidFailedWithError:)]) 
    {
        [self.delegate vkontakteDidFailedWithError:error];
    }
}

- (void)authorizationDidCanceled
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(vkontakteAuthControllerDidCancelled)]) 
    {
        [self.delegate vkontakteAuthControllerDidCancelled];
    }
}

- (void)didFinishGettingUserEmail:(NSString *)_email
{
    email = _email;
}

@end
