/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBJSONSerializationDescribeable.h>

@class FBSimulator;
@class FBSimulatorFramebuffer;
@class FBSimulatorLaunchConfiguration;

/**
 A Simulator Bridge is a container for all of the relevant services that can be obtained when launching via: -[SimDevice bootWithOptions:error].
 Typically these are all the services with which Simulator.app can interact with, except that we have them inside FBSimulatorControl.
 */
@interface FBSimulatorBridge : NSObject  <FBJSONSerializationDescribeable>

/**
 Creates a Simulator Bridge by booting the provided Simulator.

 @param simulator the Simulator to boot and bridge.
 @param configuration the Configuration for configuring the Framebuffer.
 @param error an error out for any error that occurs.
 @return a Simulator Bridge for the given Simulator on success, nil otherwise.
 */
+ (instancetype)bootSimulator:(FBSimulator *)simulator withConfiguration:(FBSimulatorLaunchConfiguration *)configuration andAttachBridgeWithError:(NSError **)error;

/**
 The Framebuffer of the Bridge.
 */
@property (nonatomic, strong, readonly) FBSimulatorFramebuffer *framebuffer;

/**
 Tears down the bridge and it's resources.
 Must only ever be called from the main thread.
 */
- (void)terminate;

/**
 Sets the first available Location Scenario on the Simulator.
 Must only ever be called from the main thread.
 */
- (void)enableLocationScenario;

@end
