/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetCommandForwarder.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Defines an interface for erasing a target.
 */
@protocol FBEraseCommands <NSObject, FBiOSTargetCommand>

#pragma mark Erase

/**
 Erases the target, with a descriptive message in the event of a failure.

 @return a Future that resolves when the target has been erased.
 */
- (FBFuture<NSNull *> *)erase;

@end

NS_ASSUME_NONNULL_END
