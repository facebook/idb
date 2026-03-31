/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>

/**
 Helpers to work around Swift limitations with ObjC APIs.
 - futureWithFutures: is NS_SWIFT_UNAVAILABLE
 */
@interface FBFutureTestHelpers : NSObject

+ (nonnull FBFuture<NSArray *> *)combineFutures:(nonnull NSArray *)futures;
+ (nonnull FBFuture *)applyTimeout:(NSTimeInterval)timeout description:(nonnull NSString *)description toFuture:(nonnull FBFuture *)future;

@end
