/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBDevice;

@protocol FBDeviceRecoveryCommandsProtocol <FBiOSTargetCommand>

/**
 Enters recovery mode.

 @return a Future that resolves when put into recovery.
 */
- (nonnull FBFuture<NSNull *> *)enterRecovery;

/**
 Exits recovery mode.

 @return a Future that resolves when removed from recovery.
 */
- (nonnull FBFuture<NSNull *> *)exitRecovery;

@end

/**
 An Implementation of FBDeviceRecoveryCommands for Devices
 */
@interface FBDeviceRecoveryCommands : NSObject <FBDeviceRecoveryCommandsProtocol>

@end
