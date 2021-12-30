/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorIndigoHID.h"

#import <SimulatorApp/Indigo.h>
#import <FBControlCore/FBControlCore.h>

#import <mach/mach.h>
#import <mach/mach_time.h>

#include <dlfcn.h>
#include <malloc/malloc.h>

#import "FBSimulatorControlFrameworkLoader.h"

typedef struct {
  IndigoMessage *(*MessageForButton)(int keyCode, int op, int target);
  IndigoMessage *(*MessageForKeyboardArbitrary)(int keyCode, int op);
  IndigoMessage *(*MessageForMouseNSEvent)(CGPoint *point0, CGPoint *point1, int target, int eventType, BOOL something);
} IndigoCalls;

@interface FBSimulatorIndigoHID ()

@property (nonatomic, assign, readonly) IndigoCalls calls;

- (instancetype)initWithCalls:(IndigoCalls)calls;

@end

@implementation FBSimulatorIndigoHID

#pragma mark Initializers

+ (instancetype)simulatorKitHIDWithError:(NSError **)error
{
  if (![FBSimulatorControlFrameworkLoader.xcodeFrameworks loadPrivateFrameworks:nil error:error]) {
    return nil;
  }
  void *handle = [[NSBundle bundleWithIdentifier:@"com.apple.SimulatorKit"] dlopenExecutablePath];
  const IndigoCalls calls = {
    .MessageForButton = FBGetSymbolFromHandle(handle, "IndigoHIDMessageForButton"),
    .MessageForKeyboardArbitrary = FBGetSymbolFromHandle(handle, "IndigoHIDMessageForKeyboardArbitrary"),
    .MessageForMouseNSEvent = FBGetSymbolFromHandle(handle, "IndigoHIDMessageForMouseNSEvent"),
  };
  return [[self alloc] initWithCalls:calls];
}

- (instancetype)initWithCalls:(IndigoCalls)calls
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _calls = calls;

  return self;
}

#pragma mark Public

- (NSData *)keyboardWithDirection:(FBSimulatorHIDDirection)direction keyCode:(unsigned int)keyCode
{
  size_t messageSize;
  IndigoMessage *message = [self keyboardMessageWithDirection:direction keyCode:keyCode messageSizeOut:&messageSize];
  return [NSData dataWithBytesNoCopy:message length:messageSize freeWhenDone:YES];
}

- (NSData *)buttonWithDirection:(FBSimulatorHIDDirection)direction button:(FBSimulatorHIDButton)button
{
  size_t messageSize;
  IndigoMessage *message = [self buttonMessageWithDirection:direction button:button messageSizeOut:&messageSize];
  return [NSData dataWithBytesNoCopy:message length:messageSize freeWhenDone:YES];
}

- (NSData *)touchScreenSize:(CGSize)screenSize direction:(FBSimulatorHIDDirection)direction x:(double)x y:(double)y
{
  return [self touchScreenSize:screenSize screenScale:1.0 direction:direction x:x y:y];
}

- (NSData *)touchScreenSize:(CGSize)screenSize screenScale:(float)screenScale direction:(FBSimulatorHIDDirection)direction x:(double)x y:(double)y
{
  // Convert Screen Offset to Ratio for Indigo.
  CGPoint point = [self.class screenRatioFromPoint:CGPointMake(x, y) screenSize:screenSize screenScale:screenScale];
  size_t messageSize;
  IndigoMessage *message = [self touchMessageWithPoint:point direction:direction messageSizeOut:&messageSize];
  return [NSData dataWithBytesNoCopy:message length:messageSize freeWhenDone:YES];
}

#pragma mark Event Generation

- (IndigoMessage *)keyboardMessageWithDirection:(FBSimulatorHIDDirection)direction keyCode:(unsigned int)keycode messageSizeOut:(size_t *)messageSizeOut
{
  IndigoMessage *message = self.calls.MessageForKeyboardArbitrary((int) keycode, direction);
  if (messageSizeOut) {
    *messageSizeOut = malloc_size(message);
  }
  return message;
}

- (IndigoMessage *)buttonMessageWithDirection:(FBSimulatorHIDDirection)direction button:(FBSimulatorHIDButton)button messageSizeOut:(size_t *)messageSizeOut
{
  IndigoMessage *message = self.calls.MessageForButton((int) [FBSimulatorIndigoHID eventSourceForButton:button], direction, ButtonEventTargetHardware);
  if (messageSizeOut) {
    *messageSizeOut = malloc_size(message);
  }
  return message;
}

- (IndigoMessage *)touchMessageWithPoint:(CGPoint)point direction:(FBSimulatorHIDDirection)direction messageSizeOut:(size_t *)messageSizeOut
{
  IndigoMessage *message = self.calls.MessageForMouseNSEvent(&point, 0x0, 0x32, (int) [FBSimulatorIndigoHID eventTypeForDirection:direction], 0x0);
  message->payload.event.touch.xRatio = point.x;
  message->payload.event.touch.yRatio = point.y;
  return [FBSimulatorIndigoHID touchMessageWithPayload:&(message->payload.event.touch) messageSizeOut:messageSizeOut];
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

+ (CGPoint)screenRatioFromPoint:(CGPoint)point screenSize:(CGSize)screenSize screenScale:(float)screenScale
{
  return CGPointMake(
    (point.x * screenScale) / screenSize.width,
    (point.y * screenScale) / screenSize.height
  );
}

+ (IndigoMessage *)touchMessageWithPayload:(IndigoTouch *)payload messageSizeOut:(size_t *)messageSizeOut
{
  // Sizes for the message + payload.
  // The size should be 320/0x140
  size_t messageSize = sizeof(IndigoMessage) + sizeof(IndigoPayload);
  if (messageSizeOut) {
    *messageSizeOut = messageSize;
  }
  // The stride should be 0x90
  size_t stride = sizeof(IndigoPayload);

  // Create and set the common values
  IndigoMessage *message = calloc(0x1, messageSize);
  message->innerSize = sizeof(IndigoPayload);
  message->eventType = IndigoEventTypeTouch;
  message->payload.field1 = 0x0000000b;
  message->payload.timestamp = mach_absolute_time();

  // Copy in the Digitizer Payload from the caller.
  void *destination = &(message->payload.event.button);
  void *source = payload;
  memcpy(destination, source, sizeof(IndigoTouch));

  // Duplicate the first IndigoPayload.
  // Also need to set the bits at (0x30 + 0x90) to 0x1.
  // On 32-Bit Archs this is equivalent this is done with a long to stomp over both fields:
  // uintptr_t mem = (uintptr_t) message;
  // mem += 0xc0;
  // int64_t *val = (int64_t *)mem;
  // *val = 0x200000001;
  source = &(message->payload);
  destination = source;
  destination += stride;
  IndigoPayload *second = (IndigoPayload *) destination;
  memcpy(destination, source, stride);

  // Adjust the second payload slightly.
  second->event.touch.field1 = 0x00000001;
  second->event.touch.field2 = 0x00000002;

  return message;
}


@end

