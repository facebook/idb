/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import <FBDeviceControl/FBDeviceCommands.h>

NS_ASSUME_NONNULL_BEGIN

@class FBDevice;

/**
 The Protocol for defining Device Activations.
 */
@protocol FBDeviceActivationCommands <FBiOSTargetCommand>

/**
 Activates the iOS Device.
 If the device is already activated, then will succeed.
 If the device activation state could not be determined, this will fail.

 @return A future that resolves when the device activates.
 */
- (FBFuture<NSNull *> *)activate;

@end

/**
 An Implementation of FBDeviceActivationCommands.
 URLs used in the activation process can be overriden via IDB_DRM_HANDSHAKE_URL & IDB_ACTIVATION_URL environment variables.
 */
@interface FBDeviceActivationCommands : NSObject <FBDeviceActivationCommands>

@end

NS_ASSUME_NONNULL_END
