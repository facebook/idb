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
 Defines an interface for power related commands.
 */
@protocol FBPowerCommands <NSObject, FBiOSTargetCommand>

/**
 Shuts the target down.
 Will fail if the target is not booted.

 @return a Future that resolves when the target has shut down.
 */
- (FBFuture<NSNull *> *)shutdown;

/**
 Reboots the target.
 Will fail if the target is not booted.

 @return a Future that resolves when the target has shut rebooted.
 */
- (FBFuture<NSNull *> *)reboot;

@end

NS_ASSUME_NONNULL_END
