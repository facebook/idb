/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBJSONConversion.h>

#import <FBSimulatorControl/FBSimulatorHID.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A Value representing a call to the HID System.
 */
@interface FBSimulatorHIDEvent : NSObject <NSCopying, FBJSONSerializable, FBJSONDeserializable>

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
 Materializes the event, performing it on the hid object.

 @param hid the hid to perform on.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)performOnHID:(FBSimulatorHID *)hid error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
