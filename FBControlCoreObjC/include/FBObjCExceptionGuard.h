/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Error domain for NSException -> NSError conversions performed by FBObjCExceptionGuard.
extern NSString *const FBObjCExceptionGuardErrorDomain;

/// Keys added to the converted NSError's userInfo.
extern NSString *const FBObjCExceptionGuardExceptionNameKey;
extern NSString *const FBObjCExceptionGuardExceptionUserInfoKey;
extern NSString *const FBObjCExceptionGuardCallStackSymbolsKey;

/**
 Bridges `NSException` raises into `NSError`s Swift can catch: an uncaught `NSException` crossing a
 Swift frame goes to `libc++abi` and terminates the process. The error is in
 `FBObjCExceptionGuardErrorDomain`; `reason` becomes `localizedDescription` and `name`, `userInfo`
 and `callStackSymbols` are preserved under the keys above. Swift callers should use
 `FBObjCExceptionGuard.guarded`.
 */
@interface FBObjCExceptionGuard : NSObject

/**
 Runs `block` under @try/@catch (NSException *). Bridged to Swift as the throwing `run(_:)`.
 */
+ (BOOL)tryBlock:(NS_NOESCAPE void (^)(void))block error:(NSError *_Nullable *_Nullable)error
  NS_SWIFT_NAME(run(_:));

@end

NS_ASSUME_NONNULL_END
