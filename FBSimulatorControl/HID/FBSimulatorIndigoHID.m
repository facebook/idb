/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorIndigoHID.h"

#include <dlfcn.h>
#import <mach/mach.h>
#import <mach/mach_time.h>

#import <FBControlCore/FBControlCore.h>
#import <SimulatorApp/Indigo.h>
#include <malloc/malloc.h>

#import "FBSimulatorControlFrameworkLoader.h"

typedef struct {
  IndigoMessage *(*MessageForButton)(int keyCode, int op, int target);
  IndigoMessage *(*MessageForKeyboardArbitrary)(int keyCode, int op);
  IndigoMessage *(*MessageForMouseNSEvent)(CGPoint *point0, CGPoint *point1, int target, int eventType, BOOL something);
} IndigoCalls;

@interface FBSimulatorIndigoHID ()

@property (nonatomic, readonly, assign) IndigoCalls calls;

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

- (NSData *)touchScreenSize:(CGSize)screenSize screenScale:(float)screenScale direction:(FBSimulatorHIDDirection)direction x:(double)x y:(double)y
{
  // Convert Screen Offset to Ratio for Indigo.
  CGPoint point = [self.class screenRatioFromPoint:CGPointMake(x, y) screenSize:screenSize screenScale:screenScale];
  size_t messageSize;
  IndigoMessage *message = [self touchMessageWithPoint:point direction:direction messageSizeOut:&messageSize];
  return [NSData dataWithBytesNoCopy:message length:messageSize freeWhenDone:YES];
}

- (NSData *)twoFingerTouchScreenSize:(CGSize)screenSize screenScale:(float)screenScale direction:(FBSimulatorHIDDirection)direction
                             finger1:(CGPoint)finger1 finger2:(CGPoint)finger2
{
  CGPoint ratio1 = [self.class screenRatioFromPoint:finger1 screenSize:screenSize screenScale:screenScale];
  CGPoint ratio2 = [self.class screenRatioFromPoint:finger2 screenSize:screenSize screenScale:screenScale];

  // Passing a non-NULL point1 makes IndigoHIDMessageForMouseNSEvent produce a
  // 3-payload message with eventType=0x03 (multi-touch) instead of 0x02 (single-touch).
  IndigoMessage *message = self.calls.MessageForMouseNSEvent(&ratio1, &ratio2, 0x32, (int) [FBSimulatorIndigoHID eventTypeForDirection:direction], 0x0);
  size_t messageSize = malloc_size(message);

  // The function does not store our coordinates directly — patch them manually.
  // Byte offsets derived from Indigo.h struct layout (IndigoPayload stride = 0xA0):
  //   Payload 1 (finger 1) at 0x20:  xRatio at 0x3C, yRatio at 0x44
  //   Payload 2 (digitizer) at 0xC0: xRatio at 0xDC, yRatio at 0xE4
  //   Payload 3 (finger 2) at 0x160: xRatio at 0x17C, yRatio at 0x184
  char *bytes = (char *)message;

  // Finger 1
  memcpy(bytes + 0x3C, &ratio1.x, sizeof(double));
  memcpy(bytes + 0x44, &ratio1.y, sizeof(double));

  // Digitizer summary (mirrors finger 1)
  memcpy(bytes + 0xDC, &ratio1.x, sizeof(double));
  memcpy(bytes + 0xE4, &ratio1.y, sizeof(double));

  // Finger 2
  memcpy(bytes + 0x17C, &ratio2.x, sizeof(double));
  memcpy(bytes + 0x184, &ratio2.y, sizeof(double));

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
    default:
      NSAssert(NO, @"Button Code %lul is not known", (unsigned long)button);
      abort();
  }
}

+ (unsigned int)eventTypeForDirection:(FBSimulatorHIDDirection)direction
{
  switch (direction) {
    case FBSimulatorHIDDirectionDown:
      return ButtonEventTypeDown;
    case FBSimulatorHIDDirectionUp:
      return ButtonEventTypeUp;
    default:
      NSAssert(NO, @"Direction Code %lul is not known", (unsigned long)direction);
      abort();
  }
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
