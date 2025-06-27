/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(unsigned int, FBSimulatorDeviceOrientation) {
  FBSimulatorDeviceOrientationPortrait = 1,
  FBSimulatorDeviceOrientationPortraitUpsideDown = 2,
  FBSimulatorDeviceOrientationLandscapeLeft = 3,
  FBSimulatorDeviceOrientationLandscapeRight = 4
};


/**
 Commands to change the device orientation
 */
@protocol FBDeviceOrientationCommands <NSObject, FBiOSTargetCommand>

/**
 Sets the device orientation

 @return A future that when the orientation change has been dispatched
 */
- (FBFuture<NSNull*> *)setDeviceOrientation:(FBSimulatorDeviceOrientation)deviceOrientation;

@end

NS_ASSUME_NONNULL_END

