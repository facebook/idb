/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;

/**
 Interactions dependent on the existence of an FBSimulatorConnection on a booted Simulator.
 */
@protocol FBSimulatorBridgeCommands <NSObject>

/**
 Sets latitude and longitude of the Simulator.
 The behaviour of a directly-launched Simulator differs from Simulator.app slightly, in that the location isn't automatically set.
 Simulator.app will typically set a location from NSUserDefaults, so Applications will have a default location.

 @param latitude the latitude of the location.
 @param longitude the longitude of the location.
 @return a Future that resolves when the location has been sent.
 */
- (FBFuture<NSNull *> *)setLocationWithLatitude:(double)latitude longitude:(double)longitude;

@end

/**
 The implementation of FBSimulatorBridgeCommands
 */
@interface FBSimulatorBridgeCommands : NSObject <FBSimulatorBridgeCommands, FBiOSTargetCommand>

@end

NS_ASSUME_NONNULL_END
