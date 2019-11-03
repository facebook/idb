/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The Action Type for a Log Tail.
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeLogTail;

/**
 The configuration for tailing a log.
 */
@interface FBLogTailConfiguration : NSObject <FBiOSTargetFuture, NSCopying>

/**
 The Designated Initializer.

 @param arguments the arguments to the log command.
 @return a new Log Tail Configuration.
 */
+ (instancetype)configurationWithArguments:(NSArray<NSString *> *)arguments;

/**
 The Arguments to the log command.
 */
@property (nonatomic, copy, readonly) NSArray<NSString *> *arguments;

@end

NS_ASSUME_NONNULL_END
