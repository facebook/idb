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
 A class for wrapping `dispatch_source` with some conveniences.
 */
@interface FBDispatchSourceNotifier : NSObject

#pragma mark Constructors

/**
 A future that resolves when the given process identifier terminates.

 @param processIdentifier the process identifier to observe.
 @return a Future that resolves when the process identifier terminates, with the process identifier.
 */
+ (FBFuture<NSNumber *> *)processTerminationFutureNotifierForProcessIdentifier:(pid_t)processIdentifier;

@end

NS_ASSUME_NONNULL_END
