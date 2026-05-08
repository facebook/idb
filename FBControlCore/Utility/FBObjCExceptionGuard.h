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
 Bridges Objective-C `NSException` raises into a form Swift can handle.

 Swift's `do/catch` only handles types conforming to `Swift.Error`. An
 uncaught `NSException` crossing a Swift frame goes straight to `libc++abi`
 and terminates the process. Any Swift call site that messages an
 Objective-C API which may raise (private framework forwarders,
 `NSProxy`-based remote proxies, anything where the receiver does not
 strictly implement every selector its declared protocols claim) should
 funnel the call through this guard.

 The guard wraps a block in `@try`/`@catch (NSException *)`. If the block
 raises, the exception is converted to an `NSError` in the
 `FBObjCExceptionGuardErrorDomain`. The error's `localizedDescription`
 carries the exception's `reason`; the original `name`, `userInfo`, and
 `callStackSymbols` are preserved under the keys above.

 Only one ObjC entry point is provided. The Swift extension on this class
 (`FBObjCExceptionGuard.guarded`) wraps it into a generic throwing API
 that captures the closure's return value via local state. That is the
 form Swift call sites should normally use.
 */
@interface FBObjCExceptionGuard : NSObject

/**
 Run a block under @try/@catch (NSException *).

 In Swift this is auto-bridged to a throwing form:
   `try FBObjCExceptionGuard.tryBlock { … }`

 @param block The block to invoke.
 @param error On failure, populated with an NSError describing the caught NSException.
 @return YES on success, NO if the block raised an NSException.
 */
+ (BOOL)tryBlock:(NS_NOESCAPE void (^)(void))block error:(NSError *_Nullable *_Nullable)error
  NS_SWIFT_NAME(run(_:));

@end

NS_ASSUME_NONNULL_END
