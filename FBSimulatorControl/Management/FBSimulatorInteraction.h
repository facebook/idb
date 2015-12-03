/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBInteraction.h>
#import <FBSimulatorControl/FBSimulator.h>

@class FBSimulator;
@class FBSimulatorApplication;
@class FBSimulatorConfiguration;
@class FBSimulatorSessionLifecycle;

/**
 Pre-session interactions used pre-launch of a Simulator
 */
@interface FBSimulatorInteraction : FBInteraction

/**
 Returns a new Interaction for the provided Simulator.

 @param simulator the Simulator to interact with, must not be nil.
 @param lifecycle the Lifecycle object to update with changes. May be nil.
 */
+ (instancetype)withSimulator:(FBSimulator *)simulator lifecycle:(FBSimulatorSessionLifecycle *)lifecycle;

/**
 Boots the simulator.
 */
- (instancetype)bootSimulator;

/**
 Opens the provided URL on the Device
 */
- (instancetype)openURL:(NSURL *)url;

@end
