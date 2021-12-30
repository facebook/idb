/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBDevice;

@protocol FBDeviceRecoveryCommands <FBiOSTargetCommand>

/**
 Enters recovery mode.

 @return a Future that resolves when put into recovery.
 */
- (FBFuture<NSNull *> *)enterRecovery;

/**
 Exits recovery mode.

 @return a Future that resolves when removed from recovery.
 */
- (FBFuture<NSNull *> *)exitRecovery;

@end

/**
 An Implementation of FBCrashLogCommand for Devices
 */
@interface FBDeviceRecoveryCommands : NSObject <FBDeviceRecoveryCommands>

@end

NS_ASSUME_NONNULL_END
