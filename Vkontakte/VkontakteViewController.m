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

#import "VkontakteViewController.h"

NSString * VkErrorDomain = @"VkErrorDomain";
NSInteger VkAuthErrorCode = 1;

@interface VkontakteViewController ()

@property (nonatomic) BOOL isViewAppeared;

@property (strong, nonatomic) UIViewController * baseViewController;
@property (strong, nonatomic) VkAuthSuccessHandler success;
@property (strong, nonatomic) VkAuthFailureHandler failure;
@property (strong, nonatomic) VkAuthCancelHandler cancel;

@end

@implementation VkontakteViewController

@synthesize delegate;
@synthesize
isViewAppeared = _isViewAppeared;

- (id)initWithAuthLink:(NSURL *)link
    baseViewController:baseViewController
               success:(VkAuthSuccessHandler)success
               failure:(VkAuthFailureHandler)failure
                cancel:(VkAuthCancelHandler)cancel
{
    self = [super init];
    if (self) 
    {
        _authLink = link;
        self.baseViewController = baseViewController;
        self.success = success;
        self.failure = failure;
        self.cancel = cancel;
    }
    return self;
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Отмена" 
                                                                              style:UIBarButtonItemStyleBordered 
                                                                             target:self 
                                                                             action:@selector(cancelButtonPressed:)];
    CGRect frame = CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height);
    _webView = [[UIWebView alloc] initWithFrame:frame];
    _webView.autoresizesSubviews = YES;
    _webView.autoresizingMask=(UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth);
    _webView.delegate = self;
    [self.view addSubview:_webView];
    [_webView loadRequest:[NSURLRequest requestWithURL:_authLink]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    self.isViewAppeared = NO;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    self.isViewAppeared = YES;
    
    if (![_webView isLoading]) {
        [self handleWebViewDidFinishLoad:_webView];
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (void)cancelButtonPressed:(id)sender
{
    [self.baseViewController dismissViewControllerAnimated:YES
                                                completion:
     ^{
         self.cancel();
     }];
}

#pragma mark - WebViewDelegate

- (void)webViewDidStartLoad:(UIWebView *)webView
{
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES]; 
    _hud = [[MBProgressHUD alloc] initWithView:self.navigationController.view];
    [self.navigationController.view addSubview:_hud];
	_hud.dimBackground = YES;
    _hud.delegate = self;
    [_hud show:YES];
}



- (void)webViewDidFinishLoad:(UIWebView *)webView {
    if (self.isViewAppeared) {
        [self handleWebViewDidFinishLoad:webView];
    }
    
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
    [_hud hide:YES];
    [_hud removeFromSuperview];
	_hud = nil;
}

typedef enum {
    VkUrlStringParseResultCode,
    VkUrlStringParseResultError,
    VkUrlStringParseResultNothing,
} VkUrlStringParseResult;

NSString * stringBetweenStrings(NSString * start, NSString * end, NSString * innerString) {
    NSScanner * scanner = [NSScanner scannerWithString:innerString];
    [scanner setCharactersToBeSkipped:nil];
    [scanner scanUpToString:start intoString:nil];
    if ([scanner scanString:start intoString:nil])
    {
        NSString* result = nil;
        if ([scanner scanUpToString:end intoString:&result])
        {
            return result;
        }
    }
    return nil;
}

VkUrlStringParseResult parseUrlString(NSString * urlString, NSString ** code, NSError ** error) {
    NSString * codeString = stringBetweenStrings(@"blank.html#code=", @"&", urlString);
    if (codeString) {
        *code = codeString;
        return VkUrlStringParseResultCode;
    } else {
        if ([urlString rangeOfString:@"error"].location != NSNotFound) {
            //todo: parse error_description
            *error = [NSError errorWithDomain:VkErrorDomain code:VkAuthErrorCode userInfo:@{NSLocalizedDescriptionKey : @"Vk auth error"}];
            return VkUrlStringParseResultError;
        } else {
            return VkUrlStringParseResultNothing;
        }
    }
}

- (void)handleWebViewDidFinishLoad:(UIWebView *)webView
{
    NSString * webViewText = [_webView stringByEvaluatingJavaScriptFromString:@"document.documentElement.innerText"];
    
    if ([webViewText caseInsensitiveCompare:@"security breach"] == NSOrderedSame) 
    {
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Невозможно авторизироваться" 
                                                        message:@"Возможно Вы пытаетесь зайти из необычного места. Попробуйте авторизироваться на сайте vk.com и повторите попытку" 
                                                       delegate:nil 
                                              cancelButtonTitle:@"Ok" 
                                              otherButtonTitles:nil, nil];
        [alert show];
        
        [self.baseViewController dismissViewControllerAnimated:YES
                                                    completion:
         ^{
             self.failure([NSError errorWithDomain:VkErrorDomain code:VkAuthErrorCode userInfo:@{NSLocalizedDescriptionKey : @"Vk auth error"}]);
         }];
    }
    
    /*
     WARNING: these two "code" params were "access_token" initially.
     This quick patch allows us to use VK's code auth mechanism instead of getting an access token right here.
     It means that the other VK functions in this lib are now broken.
     To fix this, we need to request our own access_token using the code we've just received.
     */
    else {
        NSString * code;
        NSError * error;
        switch (parseUrlString(webView.request.URL.absoluteString, &code, &error)) {
            case VkUrlStringParseResultCode: {
                [self.baseViewController dismissViewControllerAnimated:YES
                                                            completion:
                 ^{
                     self.success(code);
                 }];
            } break;
            case VkUrlStringParseResultError: {
                [self.baseViewController dismissViewControllerAnimated:YES
                                                            completion:
                 ^{
                     self.failure(error);
                 }];
            } break;
            case VkUrlStringParseResultNothing: {
            } break;
            default: assert(NO);
        }
    }
}

-(void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error 
{
    
    NSLog(@"vkWebView Error: %@", [error localizedDescription]);
    if (self.delegate && [self.delegate respondsToSelector:@selector(authorizationDidFailedWithError:)]) 
    {
        [self.delegate authorizationDidFailedWithError:error];
    }
    
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];  
    [_hud hide:YES];
    [_hud removeFromSuperview];
	_hud = nil;
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType 
{    
    NSString *s = @"var filed = document.getElementsByClassName('filed'); "
    "var textField = filed[0];"
    "textField.value;";            
    NSString *email = [webView stringByEvaluatingJavaScriptFromString:s];
    if (([email length] != 0) && _userEmail == nil) 
    {
        _userEmail = email;
    }
    
    NSURL *URL = [request URL];
    // Пользователь нажал Отмена в веб-форме
    if ([[URL absoluteString] isEqualToString:@"http://api.vk.com/blank.html#error=access_denied&error_reason=user_denied&error_description=User%20denied%20your%20request"]) 
    {
        if (self.delegate && [self.delegate respondsToSelector:@selector(authorizationDidCanceled)]) 
        {
            [self.delegate authorizationDidCanceled];
        }
        return NO;
    }
	NSLog(@"Request: %@", [URL absoluteString]); 
	return YES;
}

@end
