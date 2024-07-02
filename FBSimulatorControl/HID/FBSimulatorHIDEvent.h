/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import <FBSimulatorControl/FBSimulatorHID.h>

NS_ASSUME_NONNULL_BEGIN

extern double const DEFAULT_SWIPE_DELTA;

/**
 A Value representing a call to the HID System.
 */
@interface FBSimulatorHIDEvent : NSObject <NSCopying>

#pragma mark Initializers

/**
 A HID Event that is a touch-down followed by an immediate touch-up.

 @param x the x-coordinate from the top left.
 @param y the y-coordinate from the top left.
 @return a new HID event.
 */
+ (instancetype)tapAtX:(double)x y:(double)y;

/**
 A HID Event that is a down followed by an immediate up.

 @param button the button to use.
 @return a new HID Event.
 */
+ (instancetype)shortButtonPress:(FBSimulatorHIDButton)button;

/**
 A HID Event for the keyboard is a down followed by an immediate up.

 @param keyCode the Key Code to send.
 @return a new HID Event.
 */
+ (instancetype)shortKeyPress:(unsigned int)keyCode;

/**
 A HID touch down event.

 @param x the x-coordinate from the top left.
 @param y the y-coordinate from the top left.
 @return a new HID event.
 */
+ (instancetype)touchDownAtX:(double)x y:(double)y;

/**
 A HID touch up event.

 @param x the x-coordinate from the top left.
 @param y the y-coordinate from the top left.
 @return a new HID event.
 */
+ (instancetype)touchUpAtX:(double)x y:(double)y;

/**
 A HID Event that press the button down.

 @param button the button to use.
 @return a new HID Event.
 */
+ (instancetype)buttonDown:(FBSimulatorHIDButton)button;

/**
 A HID Event that press the button up.

 @param button the button to use.
 @return a new HID Event.
 */
+ (instancetype)buttonUp:(FBSimulatorHIDButton)button;

/**
 A HID Event from the keyboard that press the key up.

 @param keyCode the Key Code to send.
 @return a new HID Event.
 */
+ (instancetype)keyUp:(unsigned int)keyCode;

/**
 A HID Event from the keyboard that press the key down.

 @param keyCode the Key Code to send.
 @return a new HID Event.
 */
+ (instancetype)keyDown:(unsigned int)keyCode;

/**
 A HID Event for sequence of shortKeyPress events.

 @param sequence a sequence of Key Codes to send.
 @return a new HID Event.
 */
+ (instancetype)shortKeyPressSequence:(NSArray<NSNumber *> *)sequence;

/**
 A HID Event for performing swipe from one point to another point. swipe is a series of tap down events along the line between the starting point and the ending point with delta pixels between points.

 @param xStart x coordinate of the starting point
 @param yStart y coordinate of the starting point
 @param xEnd x coordinate of the ending point
 @param yEnd y coordinate of the ending point
 @param delta distance between tap down events
 @return a new HID Event.
 */
+ (instancetype)swipe:(double)xStart yStart:(double)yStart xEnd:(double)xEnd yEnd:(double)yEnd delta:(double)delta duration:(double)duration;

/**
 A HID Event consisting of multiple events

 @param events an array of events
 @return a composite event
 */
+ (instancetype)eventWithEvents:(NSArray<FBSimulatorHIDEvent *> *)events;

/**
 A HID Event that delays the next event by a set duration

 @param duration Amount of time to delay the next event by in seconds
 @return a new HID Event.
 */
+ (instancetype)delay:(double)duration;

#pragma mark Public Methods

/**
 Materializes the event, performing it on the hid object.

 @param hid the hid to perform on.
 @return A future that resolves when the event has been sent.
 */
- (FBFuture<NSNull *> *)performOnHID:(FBSimulatorHID *)hid;

@end

NS_ASSUME_NONNULL_END
