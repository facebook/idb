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

#import <FBSimulatorControl/FBSimulatorIndigoHID.h>

@class FBSimulator;

NS_ASSUME_NONNULL_BEGIN

/**
 A Wrapper around the mach_port_t that is created in the booting of a Simulator.
 The IndigoHIDRegistrationPort is essential for backboard, otherwise UI events aren't synthesized properly.
 */
@interface FBSimulatorHID : NSObject <FBJSONSerializable>

#pragma mark Initializers

/**
 Creates and returns a FBSimulatorHID Instance for the provided Simulator.
 Will fail if a HID Port could not be registered for the provided Simulator.
 Registration should occur prior to booting the Simulator.

 @param simulator the Simulator to create a IndigoHIDRegistrationPort for.
 @param error an error out for any error that occurs.
 @return a FBSimulatorHID if successful, nil otherwise.
 */
+ (instancetype)hidPortForSimulator:(FBSimulator *)simulator error:(NSError **)error;

#pragma mark Lifecycle

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
 Sends a Keyboard Event.

 @param direction the direction of the event.
 @param keycode the Key Code to send. The keycodes are 'Hardware Independent' as described in <HIToolbox/Events.h>.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)sendKeyboardEventWithDirection:(FBSimulatorHIDDirection)direction keyCode:(unsigned int)keycode error:(NSError **)error;

/**
 Sends a Button Event.

 @param direction the direction of the event.
 @param button the button.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)sendButtonEventWithDirection:(FBSimulatorHIDDirection)direction button:(FBSimulatorHIDButton)button error:(NSError **)error;

/**
 Sends a Tap Event
 Will Perform the Touch Down, followed by the Touch Up

 @param type the event type.
 @param x the X-Coordinate
 @param y the Y-Coordinate
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)sendTouchWithType:(FBSimulatorHIDDirection)type x:(double)x y:(double)y error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
