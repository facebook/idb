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
@protocol FBSimulatorBridgeCommands

/**
 Sets latitude and longitude of the Simulator.
 The behaviour of a directly-launched Simulator differs from Simulator.app slightly, in that the location isn't automatically set.
 Simulator.app will typically set a location from NSUserDefaults, so Applications will have a default location.

 @param latitude the latitude of the location.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)setLocation:(double)latitude longitude:(double)longitude error:(NSError **)error;

@end

/**
 The implementation of FBSimulatorBridgeCommands
 */
@interface FBSimulatorBridgeCommands : NSObject <FBSimulatorBridgeCommands, FBiOSTargetCommand>

@end

NS_ASSUME_NONNULL_END
