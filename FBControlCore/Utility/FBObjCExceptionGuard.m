/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBObjCExceptionGuard.h"

NSString *const FBObjCExceptionGuardErrorDomain = @"com.facebook.FBObjCExceptionGuard";
NSString *const FBObjCExceptionGuardExceptionNameKey = @"FBObjCExceptionGuardExceptionName";
NSString *const FBObjCExceptionGuardExceptionUserInfoKey = @"FBObjCExceptionGuardExceptionUserInfo";
NSString *const FBObjCExceptionGuardCallStackSymbolsKey = @"FBObjCExceptionGuardCallStackSymbols";

@implementation FBObjCExceptionGuard

+ (NSError *)errorFromException:(NSException *)exception
{
  NSMutableDictionary<NSString *, id> *userInfo = [NSMutableDictionary dictionary];
  userInfo[NSLocalizedDescriptionKey] = exception.reason ?: @"Unknown Objective-C exception";
  if (exception.name) {
    userInfo[FBObjCExceptionGuardExceptionNameKey] = exception.name;
  }
  if (exception.userInfo) {
    userInfo[FBObjCExceptionGuardExceptionUserInfoKey] = exception.userInfo;
  }
  if (exception.callStackSymbols) {
    userInfo[FBObjCExceptionGuardCallStackSymbolsKey] = exception.callStackSymbols;
  }
  return [NSError errorWithDomain:FBObjCExceptionGuardErrorDomain code:0 userInfo:userInfo];
}

+ (BOOL)tryBlock:(NS_NOESCAPE void (^)(void))block error:(NSError *_Nullable *_Nullable)error
{
  @try {
    block();
    return YES;
  } @catch (NSException *exception) {
    if (error) {
      *error = [self errorFromException:exception];
    }
    return NO;
  }
}

@end
