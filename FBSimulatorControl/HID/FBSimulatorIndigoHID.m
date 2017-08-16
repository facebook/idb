/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorIndigoHID.h"

#import <SimulatorApp/Indigo.h>
#import <FBControlCore/FBControlCore.h>

#import <mach/mach.h>
#import <mach/mach_time.h>

#include <dlfcn.h>
#include <malloc/malloc.h>

#import "FBSimulatorControlFrameworkLoader.h"

@interface FBSimulatorIndigoHID_SimulatorKit : FBSimulatorIndigoHID

@end

@interface FBSimulatorIndigoHID_Reimplemented : FBSimulatorIndigoHID

@end

@implementation FBSimulatorIndigoHID

#pragma mark Initializers

+ (instancetype)defaultHID
{
  if (FBXcodeConfiguration.isXcode9OrGreater) {
    return [self simulatorKit];
  }
  return [self reimplemented];
}

+ (instancetype)simulatorKit
{
  return [FBSimulatorIndigoHID_SimulatorKit new];
}

+ (instancetype)reimplemented
{
  return [FBSimulatorIndigoHID_Reimplemented new];
}

#pragma mark Public

- (NSData *)keyboardWithDirection:(FBSimulatorHIDDirection)direction keyCode:(unsigned int)keyCode
{
  size_t messageSize;
  IndigoMessage *message = [self.class keyboardMessageWithDirection:direction keyCode:keyCode messageSizeOut:&messageSize];
  return [NSData dataWithBytesNoCopy:message length:messageSize freeWhenDone:YES];
}

- (NSData *)buttonWithDirection:(FBSimulatorHIDDirection)direction button:(FBSimulatorHIDButton)button
{
  size_t messageSize;
  IndigoMessage *message = [self.class buttonMessageWithDirection:direction button:button messageSizeOut:&messageSize];
  return [NSData dataWithBytesNoCopy:message length:messageSize freeWhenDone:YES];
}

- (NSData *)touchScreenSize:(CGSize)screenSize direction:(FBSimulatorHIDDirection)direction x:(double)x y:(double)y
{
  // Convert Screen Offset to Ratio for Indigo.
  CGPoint point = [self.class screenRatioFromPoint:CGPointMake(x, y) screenSize:screenSize];
  size_t messageSize;
  IndigoMessage *message = [self.class touchMessageWithPoint:point direction:direction messageSizeOut:&messageSize];
  return [NSData dataWithBytesNoCopy:message length:messageSize freeWhenDone:YES];
}

#pragma mark Event Generation

+ (IndigoMessage *)keyboardMessageWithDirection:(FBSimulatorHIDDirection)direction keyCode:(unsigned int)keycode messageSizeOut:(size_t *)messageSizeOut
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

+ (IndigoMessage *)buttonMessageWithDirection:(FBSimulatorHIDDirection)direction button:(FBSimulatorHIDButton)button messageSizeOut:(size_t *)messageSizeOut
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

+ (IndigoMessage *)touchMessageWithPoint:(CGPoint)point direction:(FBSimulatorHIDDirection)direction messageSizeOut:(size_t *)messageSizeOut
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

+ (unsigned int)eventSourceForButton:(FBSimulatorHIDButton)button
{
  switch (button) {
    case FBSimulatorHIDButtonApplePay:
      return ButtonEventSourceApplePay;
    case FBSimulatorHIDButtonHomeButton:
      return ButtonEventSourceHomeButton;
    case FBSimulatorHIDButtonLock:
      return ButtonEventSourceLock;
    case FBSimulatorHIDButtonSideButton:
      return ButtonEventSourceSideButton;
    case FBSimulatorHIDButtonSiri:
      return ButtonEventSourceSiri;
  }
  NSAssert(NO, @"Button Code %lul is not known", (unsigned long)button);
}

+ (unsigned int)eventTypeForDirection:(FBSimulatorHIDDirection)direction
{
  switch (direction) {
    case FBSimulatorHIDDirectionDown:
      return ButtonEventTypeDown;
    case FBSimulatorHIDDirectionUp:
      return  ButtonEventTypeUp;
  }
  NSAssert(NO, @"Direction Code %lul is not known", (unsigned long)direction);
}

+ (CGPoint)screenRatioFromPoint:(CGPoint)point screenSize:(CGSize)screenSize
{
  return CGPointMake(
    point.x / screenSize.width,
    point.y / screenSize.height
  );
}

+ (IndigoMessage *)touchMessageWithPayload:(IndigoTouch *)payload messageSizeOut:(size_t *)messageSizeOut
{
  // Sizes for the payload.
  // The size should be 320/0x140
  size_t messageSize = sizeof(IndigoMessage) + sizeof(IndigoInner);
  if (messageSizeOut) {
    *messageSizeOut = messageSize;
  }
  // The stride should be 0x90
  size_t stride = sizeof(IndigoInner);

  // Create and set the common values
  IndigoMessage *message = calloc(0x1, messageSize);
  message->innerSize = sizeof(IndigoInner);
  message->eventType = IndigoEventTypeTouch;
  message->inner.field1 = 0x0000000b;
  message->inner.timestamp = mach_absolute_time();

  // Copy in the Digitizer Payload from the caller.
  void *destination = &(message->inner.unionPayload.button);
  void *source = payload;
  memcpy(destination, source, sizeof(IndigoTouch));

  // Duplicate the First IndigoInner Payload.
  // Also need to set the bits at (0x30 + 0x90) to 0x1.
  // On 32-Bit Archs this is equivalent this is done with a long to stomp over both fields:
  // uintptr_t mem = (uintptr_t) message;
  // mem += 0xc0;
  // int64_t *val = (int64_t *)mem;
  // *val = 0x200000001;
  source = &(message->inner);
  destination = source;
  destination += stride;
  IndigoInner *second = (IndigoInner *) destination;
  memcpy(destination, source, stride);

  // Adjust the second payload slightly.
  second->unionPayload.touch.field1 = 0x00000001;
  second->unionPayload.touch.field2 = 0x00000002;

  return message;
}

@end

@implementation FBSimulatorIndigoHID_SimulatorKit

IndigoMessage *(*IndigoHIDMessageForButton)(int keyCode, int op, int target);
IndigoMessage *(*IndigoHIDMessageForKeyboardArbitrary)(int keyCode, int op);
IndigoMessage *(*IndigoHIDMessageForMouseNSEvent)(CGPoint *point0, CGPoint *point1, int target, int eventType, BOOL something);

#pragma mark Initializers

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    [FBSimulatorIndigoHID_SimulatorKit loadAllSymbols];
  });

  return self;
}

+ (void)loadAllSymbols
{
  [FBSimulatorControlFrameworkLoader.xcodeFrameworks loadPrivateFrameworksOrAbort];
  NSBundle *frameworkBundle = [NSBundle bundleWithIdentifier:@"com.apple.SimulatorKit"];
  NSAssert(frameworkBundle, @"Framework com.apple.SimulatorKit should be loaded");
  NSString *imagePath = [frameworkBundle pathForResource:@"SimulatorKit" ofType:@""];
  void *handle = dlopen(imagePath.UTF8String, RTLD_NOW);
  IndigoHIDMessageForButton = FBGetSymbolFromHandle(handle, "IndigoHIDMessageForButton");
  IndigoHIDMessageForKeyboardArbitrary = FBGetSymbolFromHandle(handle, "IndigoHIDMessageForKeyboardArbitrary");
  IndigoHIDMessageForMouseNSEvent = FBGetSymbolFromHandle(handle, "IndigoHIDMessageForMouseNSEvent");
}

#pragma mark Event Generation

+ (IndigoMessage *)keyboardMessageWithDirection:(FBSimulatorHIDDirection)direction keyCode:(unsigned int)keycode messageSizeOut:(size_t *)messageSizeOut
{
  IndigoMessage *message = IndigoHIDMessageForKeyboardArbitrary((int) keycode, direction);
  if (messageSizeOut) {
    *messageSizeOut = malloc_size(message);
  }
  return message;
}

+ (IndigoMessage *)buttonMessageWithDirection:(FBSimulatorHIDDirection)direction button:(FBSimulatorHIDButton)button messageSizeOut:(size_t *)messageSizeOut
{
  IndigoMessage *message = IndigoHIDMessageForButton((int) [self eventSourceForButton:button], direction, ButtonEventTargetHardware);
  if (messageSizeOut) {
    *messageSizeOut = malloc_size(message);
  }
  return message;
}

+ (IndigoMessage *)touchMessageWithPoint:(CGPoint)point direction:(FBSimulatorHIDDirection)direction messageSizeOut:(size_t *)messageSizeOut
{
  IndigoMessage *message = IndigoHIDMessageForMouseNSEvent(&point, 0x0, 0x32, (int) [self eventTypeForDirection:direction], 0x0);
  message->inner.unionPayload.touch.xRatio = point.x;
  message->inner.unionPayload.touch.yRatio = point.y;
  return [self touchMessageWithPayload:&(message->inner.unionPayload.touch) messageSizeOut:messageSizeOut];
}

@end

@implementation FBSimulatorIndigoHID_Reimplemented

#pragma mark Event Generation

+ (IndigoMessage *)keyboardMessageWithDirection:(FBSimulatorHIDDirection)direction keyCode:(unsigned int)keycode messageSizeOut:(size_t *)messageSizeOut
{
  IndigoButton payload;
  payload.eventSource = ButtonEventSourceKeyboard;
  payload.eventType = [self eventTypeForDirection:direction];
  payload.eventTarget = ButtonEventTargetKeyboard;
  payload.keyCode = keycode;
  payload.field5 = 0x000000cc;

  // Then Up/Down.
  switch (direction) {
    case FBSimulatorHIDDirectionDown:
      payload.eventType = ButtonEventTypeDown;
      break;
    case FBSimulatorHIDDirectionUp:
      payload.eventType = ButtonEventTypeUp;
      break;
  }
  return [self buttonMessageWithPayload:&payload messageSizeOut:messageSizeOut];
}

+ (IndigoMessage *)buttonMessageWithDirection:(FBSimulatorHIDDirection)direction button:(FBSimulatorHIDButton)button messageSizeOut:(size_t *)messageSizeOut
{
  IndigoButton payload;
  payload.keyCode = 0;
  payload.field5 = 0;
  payload.eventSource = [self eventSourceForButton:button];
  payload.eventType = [self eventTypeForDirection:direction];
  payload.eventTarget = ButtonEventTargetHardware;

  return [self buttonMessageWithPayload:&payload messageSizeOut:messageSizeOut];
}

+ (IndigoMessage *)touchMessageWithPoint:(CGPoint)point direction:(FBSimulatorHIDDirection)direction messageSizeOut:(size_t *)messageSizeOut
{
  // Set the Common Values between down-and-up.
  IndigoTouch payload;
  payload.field1 = 0x00400002;
  payload.field2 = 0x1;
  payload.field3 = 0x3;

  // Points are the ratio between the top-left and bottom right.
  payload.xRatio = point.x;
  payload.yRatio = point.y;

  // Zero some more fields.
  payload.field6 = 0;
  payload.field7 = 0;
  payload.field8 = 0;

  // Setting the Values Signifying touch-down.
  switch (direction) {
    case FBSimulatorHIDDirectionDown:
      payload.field9 = 0x1;
      payload.field10 = 0x1;
      break;
    case FBSimulatorHIDDirectionUp:
      payload.field9 = 0x0;
      payload.field10 = 0x0;
      break;
    default:
      break;
  }

  // Setting some other fields
  payload.field11 = 0x32;
  payload.field12 = 0x1;
  payload.field13 = 0x2;
  payload.field14 = 0;
  payload.field15 = 0;
  payload.field16 = 0;
  payload.field17 = 0;
  payload.field18 = 0;

  return [self touchMessageWithPayload:&payload messageSizeOut:messageSizeOut];
}

+ (IndigoMessage *)buttonMessageWithPayload:(IndigoButton *)payload messageSizeOut:(size_t *)messageSizeOut
{
  // Create the Message.
  //The size should be 176/0xb0
  size_t messageSize = sizeof(IndigoMessage);
  if (messageSizeOut) {
    *messageSizeOut = messageSize;
  }
  IndigoMessage *message = calloc(0x1 , messageSize);

  // Set the down payload of the message.
  message->innerSize = sizeof(IndigoInner);
  message->eventType = IndigoEventTypeButton;
  message->inner.field1 = 0x2;
  message->inner.timestamp = mach_absolute_time();

  // Copy the contents of the payload.
  void *destination = &message->inner.unionPayload.button;
  void *source = (void *) payload;
  memcpy(destination, source, sizeof(IndigoButton));
  return message;
}

@end
