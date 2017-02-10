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

@class FBSimulator;

NS_ASSUME_NONNULL_BEGIN

/**
 A Wrapper around the mach_port_t that is created in the booting of a Simulator.
 The IndigoHIDRegistrationPort is essential for backboard, otherwise UI events aren't synthesized properly.
 */
@interface FBSimulatorHID : NSObject <FBDebugDescribeable, FBJSONSerializable>

/**
 Creates and returns a FBSimulatorHID Instance for the provided Simulator.
 Will fail if a HID Port could not be registered for the provided Simulator.
 Registration should occur prior to booting the Simulator.

 @param simulator the Simulator to create a IndigoHIDRegistrationPort for.
 @param error an error out for any error that occurs.
 @return a FBSimulatorHID if successful, nil otherwise.
 */
+ (instancetype)hidPortForSimulator:(FBSimulator *)simulator error:(NSError **)error;

/**
 Obtains the Reply Port for the Simulator.
 This must be obtained in order to send IndigoHID events to the Simulator.
 This should be obtained after the Simulator is booted.

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)connect:(NSError **)error;

/**
 Disconnects from the remote HID.
 */
- (void)disconnect;

#pragma mark HID Manipulation

/**
 Sends a Home Button Event.
 Will Perform the Button Down, followed by the Button Up.

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)sendHomeButtonWithError:(NSError **)error;

/**
 Sends a Tap Event
 Will Perform the Touch Down, followed by the Touch Up

 @param x the X-Coordinate
 @param y the Y-Coordinate
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)sendTapWithX:(double)x y:(double)y error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
