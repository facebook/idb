/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The logger for idb.
 */
@interface FBIDBLogger : FBCompositeLogger

#pragma mark Initializers

/**
 The Designated Initializer.

 @param userDefaults the user defaults to use.
 @return a new logger instance.
 */
+ (instancetype)loggerWithUserDefaults:(NSUserDefaults *)userDefaults;

#pragma mark Public Methods

/**
 Starts a log operation, tailing to a consumer.

 @param consumer the consumer.
 @return a future wrapping the log operation for the companion.
 */
- (FBFuture<id<FBLogOperation>> *)tailToConsumer:(id<FBDataConsumer>)consumer;

@end

NS_ASSUME_NONNULL_END
