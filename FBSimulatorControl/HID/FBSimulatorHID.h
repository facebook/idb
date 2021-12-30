/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
@interface FBSimulatorHID : NSObject

#pragma mark Initializers

/**
 Creates and returns a FBSimulatorHID Instance for the provided Simulator.
 Will fail if a HID Port could not be registered for the provided Simulator.
 Registration may need to occur prior to booting.

 @param simulator the Simulator to create a IndigoHIDRegistrationPort for.
 @return a FBSimulatorHID if successful, nil otherwise.
 */
+ (FBFuture<FBSimulatorHID *> *)hidForSimulator:(FBSimulator *)simulator;

#pragma mark Lifecycle

/**
 Obtains the Reply Port for the Simulator.
 This must be obtained in order to send IndigoHID events to the Simulator.
 This should be obtained after the Simulator is booted.

 @return A future that resolves when connected.
 */
- (FBFuture<NSNull *> *)connect;

/**
 Disconnects from the remote HID.
 
 @return A future that resolves when disconnected
 */
- (FBFuture<NSNull *> *)disconnect;

#pragma mark HID Manipulation

/**
 Sends a Keyboard Event.

 @param direction the direction of the event.
 @param keycode the Key Code to send. The keycodes are 'Hardware Independent' as described in <HIToolbox/Events.h>.
 @return A future that resolves when the event has been sent.
 */
- (FBFuture<NSNull *> *)sendKeyboardEventWithDirection:(FBSimulatorHIDDirection)direction keyCode:(unsigned int)keycode;

/**
 Sends a Button Event.

 @param direction the direction of the event.
 @param button the button.
 @return A future that resolves when the event has been sent.
 */
- (FBFuture<NSNull *> *)sendButtonEventWithDirection:(FBSimulatorHIDDirection)direction button:(FBSimulatorHIDButton)button;

/**
 Sends a Tap Event
 Will Perform the Touch Down, followed by the Touch Up

 @param type the event type.
 @param x the X-Coordinate
 @param y the Y-Coordinate
 @return A future that resolves when the event has been sent.
 */
- (FBFuture<NSNull *> *)sendTouchWithType:(FBSimulatorHIDDirection)type x:(double)x y:(double)y;

#pragma mark Properties

/**
 The Queue on which messages are sent to the HID Server.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

NS_ASSUME_NONNULL_END
