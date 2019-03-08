/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 An Enumeration for the Direction of the Event.
 */
typedef NS_ENUM(NSUInteger, FBSimulatorHIDDirection) {
  FBSimulatorHIDDirectionDown = 1,
  FBSimulatorHIDDirectionUp = 2,
};

/**
 An Enumeration Representing a button press.
 */
typedef NS_ENUM(NSUInteger, FBSimulatorHIDButton) {
  FBSimulatorHIDButtonApplePay = 1,
  FBSimulatorHIDButtonHomeButton = 2,
  FBSimulatorHIDButtonLock = 3,
  FBSimulatorHIDButtonSideButton = 4,
  FBSimulatorHIDButtonSiri = 5,
};

/**
 Translates FBSimulatorHID Events into Indigo Structs.
 */
@interface FBSimulatorIndigoHID : NSObject

/**
 The Designated Initializer
 */
+ (instancetype)defaultHID;

/**
 The SimulatorKit Implementation.
 */
+ (instancetype)simulatorKit;

/**
 The internal Implementation.
 */
+ (instancetype)reimplemented;

/**
 A Keyboard Event.

 @param direction the direction of the event.
 @param keycode the Key Code to send. The keycodes are 'Hardware Independent' as described in <HIToolbox/Events.h>.
 @return an NSData-Wrapped IndigoMessage. The data is owned by the reciever and will be freed when the data is deallocated.
 */
- (NSData *)keyboardWithDirection:(FBSimulatorHIDDirection)direction keyCode:(unsigned int)keycode;

/**
 A Button Event.

 @param direction the direction of the event.
 @param button the button.
 @return an NSData-Wrapped IndigoMessage. The data is owned by the reciever and will be freed when the data is deallocated.
 */
- (NSData *)buttonWithDirection:(FBSimulatorHIDDirection)direction button:(FBSimulatorHIDButton)button;

/**
 A Touch Event.

 @param screenSize the size of the screen in pixels.
 @param direction the direction of the event.
 @param x the X-Coordinate in pixels
 @param y the Y-Coordinate pixels
 @return an NSData-Wrapped IndigoMessage. The data is owned by the reciever and will be freed when the data is deallocated.
 */
- (NSData *)touchScreenSize:(CGSize)screenSize direction:(FBSimulatorHIDDirection)direction x:(double)x y:(double)y;


/**
 A Touch Event.
 @param screenSize the size of the screen in pixels.
 @param screenScale the scale of the screen e.g. @2x
 @param direction the direction of the event.
 @param x the X-Coordinate in pixels
 @param y the Y-Coordinate pixels
 @return an NSData-Wrapped IndigoMessage. The data is owned by the reciever and will be freed when the data is deallocated.
 */
- (NSData *)touchScreenSize:(CGSize)screenSize screenScale:(float)screenScale direction:(FBSimulatorHIDDirection)direction x:(double)x y:(double)y;

@end

NS_ASSUME_NONNULL_END
