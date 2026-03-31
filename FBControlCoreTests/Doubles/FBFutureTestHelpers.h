/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Helpers to work around Swift limitations with ObjC APIs.
 - futureWithFutures: is NS_SWIFT_UNAVAILABLE
 - timeout:waitingFor: is variadic (NS_FORMAT_FUNCTION) and can't be called from Swift
 */
@interface FBFutureTestHelpers : NSObject

+ (FBFuture<NSArray *> *)combineFutures:(NSArray *)futures;
+ (FBFuture *)applyTimeout:(NSTimeInterval)timeout description:(NSString *)description toFuture:(FBFuture *)future;

@end

NS_ASSUME_NONNULL_END
