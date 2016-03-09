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

@class FBFramebuffer;
@class FBSimulator;
@class FBSimulatorLaunchConfiguration;

/**
 A Simulator Bridge is a container for all of the relevant services that can be obtained when launching via: -[SimDevice bootWithOptions:error].
 Typically these are all the services with which Simulator.app can interact with, except that we have them inside FBSimulatorControl.
 */
@interface FBSimulatorBridge : NSObject  <FBJSONSerializable>

#pragma mark Lifecycle

/**
 Creates a Simulator Bridge by booting the provided Simulator.

 @param simulator the Simulator to boot and bridge.
 @param configuration the Configuration for configuring the Framebuffer.
 @param error an error out for any error that occurs.
 @return a Simulator Bridge for the given Simulator on success, nil otherwise.
 */
+ (instancetype)bootSimulator:(FBSimulator *)simulator withConfiguration:(FBSimulatorLaunchConfiguration *)configuration andAttachBridgeWithError:(NSError **)error;

/**
 Tears down the bridge and it's resources, waiting for any asynchronous teardown to occur before returning.
 Must only ever be called from the main thread.

 @param timeout the number of seconds to wait for termination to occur in. If 0 or fewer, the reciever won't wait.
 @return YES if the termination occurred within timeout seconds, NO otherwise.
 */
- (BOOL)terminateWithTimeout:(NSTimeInterval)timeout;

#pragma mark Interacting with the Simulator

/**
 Sets latitude and longitude of the Simulator.
 The behaviour of a directly-launched Simulator differs from Simulator.app slightly, in that the location isn't automatically set.
 Simulator.app will typically set a location from NSUserDefaults, so Applications will have a default location.

 @param latitude the latitude of the location.
 @param longitude the longitude of the location.
 */
- (void)setLocationWithLatitude:(double)latitude longitude:(double)longitude;

#pragma mark Properties

/**
 The FBSimulatorFramebuffer Instance.
 */
@property (nonatomic, strong, readonly) FBFramebuffer *framebuffer;

@end
