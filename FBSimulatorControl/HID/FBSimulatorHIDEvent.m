/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorHIDEvent.h"

#import <FBControlCore/FBControlCore.h>

#import "FBSimulatorError.h"
#import "FBSimulatorHID.h"
#import "FBSimulator.h"

static NSString *const KeyEventClass = @"class";
static NSString *const KeyDirection = @"direction";

static NSString *const EventClassStringComposite = @"composite";
static NSString *const EventClassStringTouch = @"touch";
static NSString *const EventClassStringButton = @"button";
static NSString *const EventClassStringKeyboard = @"keyboard";
static NSString *const EventClassStringDelay = @"delay";

const double DEFAULT_SWIPE_DELTA = 10.0;

static NSString *const DirectionDown = @"down";
static NSString *const DirectionUp = @"up";

static NSString * directionStringFromDirection(FBSimulatorHIDDirection direction)
{
  switch (direction) {
    case FBSimulatorHIDDirectionDown:
      return DirectionDown;
    case FBSimulatorHIDDirectionUp:
      return DirectionUp;
    default:
      return nil;
  }
}

static BOOL shouldLogHIDEventDetails(void)
{
  return NSProcessInfo.processInfo.environment[@"FBSIMULATORCONTROL_LOG_HID_DETAILS"].boolValue;
}

@interface FBSimulatorHIDEvent_Composite : NSObject <FBSimulatorHIDEvent, FBSimulatorHIDEventComposite>

@property (nonatomic, copy, readonly) NSArray<id<FBSimulatorHIDEvent>> *events;

@end

@implementation FBSimulatorHIDEvent_Composite

static NSString *const KeyEvents = @"events";

- (instancetype)initWithEvents:(NSArray<id<FBSimulatorHIDEvent>> *)events
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _events = events;
  
  return self;
}

- (FBFuture<NSNull *> *)performOnHID:(FBSimulatorHID *)hid
{
  return [self performEvents:self.events onHid:hid];
}

- (FBFuture<NSNull *> *)performEvents:(NSArray<id<FBSimulatorHIDEvent>> *)events onHid:(FBSimulatorHID *)hid
{
  if (events.count == 0) {
    return FBFuture.empty;
  }
  id<FBSimulatorHIDEvent> event = events.firstObject;
  NSArray<id<FBSimulatorHIDEvent>> *next = events.count == 1 ? @[] : [events subarrayWithRange:NSMakeRange(1, events.count - 1)];
  return [[event
    performOnHID:hid]
    onQueue:dispatch_get_main_queue() fmap:^(id _){
      return [self performEvents:next onHid:hid];
    }];
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Composite %@", [FBCollectionInformation oneLineDescriptionFromArray:self.events]];
}

- (id)copyWithZone:(NSZone *)zone
{
  // All values are immutable.
  return self;
}

- (BOOL)isEqual:(FBSimulatorHIDEvent_Composite *)event
{
  if (![event isKindOfClass:self.class]) {
    return NO;
  }
  return [self.events isEqualToArray:event.events];
}

- (NSUInteger)hash
{
  return self.events.hash;
}

@end

@interface FBSimulatorHIDEvent_Touch : NSObject <FBSimulatorHIDEventPayload>

@property (nonatomic, assign, readonly) FBSimulatorHIDDirection direction;
@property (nonatomic, assign, readonly) double x;
@property (nonatomic, assign, readonly) double y;

@end

@implementation FBSimulatorHIDEvent_Touch

static NSString *const KeyX = @"x";
static NSString *const KeyY = @"y";

- (instancetype)initWithDirection:(FBSimulatorHIDDirection)direction x:(double)x y:(double)y
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _direction = direction;
  _x = x;
  _y = y;

  return self;
}

- (FBFuture<NSNull *> *)performOnHID:(FBSimulatorHID *)hid
{
  return [hid sendEvent:[self payloadForHID:hid]];
}

- (NSData *)payloadForHID:(FBSimulatorHID *)hid
{
  return [hid.indigo touchScreenSize:hid.mainScreenSize screenScale:hid.mainScreenScale direction:self.direction x:self.x y:self.y];
}

- (NSString *)description
{
  if (shouldLogHIDEventDetails()) {
    return [NSString stringWithFormat:
      @"Touch %@ at (%lu,%lu)",
      directionStringFromDirection(self.direction),
      (unsigned long)self.x,
      (unsigned long)self.y
    ];
  }
  return @"Touch <hidden>";
}

- (id)copyWithZone:(NSZone *)zone
{
  // All values are immutable.
  return self;
}

- (BOOL)isEqual:(FBSimulatorHIDEvent_Touch *)event
{
  if (![event isKindOfClass:self.class]) {
    return NO;
  }
  return self.direction == event.direction && self.x == event.x && self.y == event.y;
}

- (NSUInteger)hash
{
  return (NSUInteger) self.direction | ((NSUInteger) self.x ^ (NSUInteger) self.y);
}

@end

static NSString *const KeyButton = @"button";
static NSString *const ButtonApplePay = @"apple_pay";
static NSString *const ButtonHomeButton = @"home";
static NSString *const ButtonLock = @"lock";
static NSString *const ButtonSideButton = @"side";
static NSString *const ButtonSiri = @"siri";

@interface FBSimulatorHIDEvent_Button : NSObject <FBSimulatorHIDEventPayload>

@property (nonatomic, assign, readonly) FBSimulatorHIDDirection type;
@property (nonatomic, assign, readonly) FBSimulatorHIDButton button;

@end

@implementation FBSimulatorHIDEvent_Button

- (instancetype)initWithDirection:(FBSimulatorHIDDirection)type button:(FBSimulatorHIDButton)button
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _type = type;
  _button = button;
  return self;
}

- (FBFuture<NSNull *> *)performOnHID:(FBSimulatorHID *)hid
{
  return [hid sendEvent:[self payloadForHID:hid]];
}

- (NSData *)payloadForHID:(FBSimulatorHID *)hid
{
  return [hid.indigo buttonWithDirection:self.type button:self.button];
}

- (NSString *)description
{
  if (shouldLogHIDEventDetails()) {
    return [NSString stringWithFormat:
      @"Button %@ %@",
      [FBSimulatorHIDEvent_Button buttonStringFromButton:self.button],
      directionStringFromDirection(self.type)
    ];
  }
  return @"Button <hidden>";
}

- (id)copyWithZone:(NSZone *)zone
{
  // All values are immutable.
  return self;
}

- (BOOL)isEqual:(FBSimulatorHIDEvent_Button *)event
{
  if (![event isKindOfClass:self.class]) {
    return NO;
  }
  return self.type == event.type && self.button == event.button;
}

- (NSUInteger)hash
{
  return (NSUInteger) self.type ^ (NSUInteger) self.button;
}

+ (NSString *)buttonStringFromButton:(FBSimulatorHIDButton)button
{
  switch (button) {
    case FBSimulatorHIDButtonApplePay:
      return ButtonApplePay;
    case FBSimulatorHIDButtonHomeButton:
      return ButtonHomeButton;
    case FBSimulatorHIDButtonLock:
      return ButtonLock;
    case FBSimulatorHIDButtonSideButton:
      return ButtonSideButton;
    case FBSimulatorHIDButtonSiri:
      return ButtonSiri;
    default:
      return nil;
  }
}

+ (FBSimulatorHIDButton)buttonFromButtonString:(NSString *)buttonString
{
  if ([buttonString isEqualToString:ButtonApplePay]) {
    return FBSimulatorHIDButtonApplePay;
  }
  if ([buttonString isEqualToString:ButtonHomeButton]) {
    return FBSimulatorHIDButtonHomeButton;
  }
  if ([buttonString isEqualToString:ButtonSideButton]) {
    return FBSimulatorHIDButtonSideButton;
  }
  if ([buttonString isEqualToString:ButtonSiri]) {
    return FBSimulatorHIDButtonSiri;
  }
  if ([buttonString isEqualToString:ButtonLock]) {
    return FBSimulatorHIDButtonLock;
  }
  return 0;
}

@end

static NSString *const KeyKeycode = @"keycode";

@interface FBSimulatorHIDEvent_Keyboard : NSObject <FBSimulatorHIDEventPayload>

@property (nonatomic, assign, readonly) FBSimulatorHIDDirection direction;
@property (nonatomic, assign, readonly) unsigned int keyCode;

@end

@implementation FBSimulatorHIDEvent_Keyboard

- (instancetype)initWithDirection:(FBSimulatorHIDDirection)direction keyCode:(unsigned int)keyCode
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _direction = direction;
  _keyCode = keyCode;

  return self;
}

- (FBFuture<NSNull *> *)performOnHID:(FBSimulatorHID *)hid
{
  return [hid sendEvent:[self payloadForHID:hid]];
}

- (NSData *)payloadForHID:(FBSimulatorHID *)hid
{
  return [hid.indigo keyboardWithDirection:self.direction keyCode:self.keyCode];
}

- (NSString *)description
{
  if (shouldLogHIDEventDetails()) {
    return [NSString stringWithFormat:
      @"Keyboard Code=%d %@",
      self.keyCode,
      directionStringFromDirection(self.direction)
    ];
  }
  return @"Key <hidden>";
}

- (id)copyWithZone:(NSZone *)zone
{
  // All values are immutable.
  return self;
}

- (BOOL)isEqual:(FBSimulatorHIDEvent_Keyboard *)event
{
  if (![event isKindOfClass:self.class]) {
    return NO;
  }
  return self.direction == event.direction && self.keyCode == event.keyCode;
}

- (NSUInteger)hash
{
  return (NSUInteger) self.direction ^ (NSUInteger) self.keyCode;
}

@end

@interface FBSimulatorHIDEvent_Delay : NSObject <FBSimulatorHIDEvent, FBSimulatorHIDEventDelay>

@end

@implementation FBSimulatorHIDEvent_Delay

@synthesize duration = _duration;

static NSString *const KeyDuration = @"duration";

- (instancetype)initWithDuration:(NSTimeInterval)duration
{
  self = [super init];
  if (!self) {
    return nil;
  }
  
  _duration = duration;
  
  return self;
}

- (FBFuture<NSNull *> *)performOnHID:(FBSimulatorHID *)hid
{
  return [FBFuture futureWithDelay:self.duration future:FBFuture.empty];
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Delay for %f", self.duration];
}

- (id)copyWithZone:(NSZone *)zone
{
  // All values are immutable.
  return self;
}

- (BOOL)isEqual:(FBSimulatorHIDEvent_Delay *)event
{
  if (![event isKindOfClass:self.class]) {
    return NO;
  }
  return self.duration == event.duration;
}

- (NSUInteger)hash
{
  return (NSUInteger) self.duration;
}

@end

@implementation FBSimulatorHIDEvent

#pragma mark - Initializers

#pragma mark Single Payload Events

+ (id<FBSimulatorHIDEventPayload>)touchDownAtX:(double)x y:(double)y
{
  return [[FBSimulatorHIDEvent_Touch alloc] initWithDirection:FBSimulatorHIDDirectionDown x:x y:y];
}

+ (id<FBSimulatorHIDEventPayload>)touchUpAtX:(double)x y:(double)y
{
  return [[FBSimulatorHIDEvent_Touch alloc] initWithDirection:FBSimulatorHIDDirectionUp x:x y:y];
}

+ (id<FBSimulatorHIDEventPayload>)buttonDown:(FBSimulatorHIDButton)button
{
  return [[FBSimulatorHIDEvent_Button alloc] initWithDirection:FBSimulatorHIDDirectionDown button:button];
}

+ (id<FBSimulatorHIDEventPayload>)buttonUp:(FBSimulatorHIDButton)button
{
  return [[FBSimulatorHIDEvent_Button alloc] initWithDirection:FBSimulatorHIDDirectionUp button:button];
}

+ (id<FBSimulatorHIDEventPayload>)keyDown:(unsigned int)keyCode
{
  return [[FBSimulatorHIDEvent_Keyboard alloc] initWithDirection:FBSimulatorHIDDirectionDown keyCode:keyCode];
}

+ (id<FBSimulatorHIDEventPayload>)keyUp:(unsigned int)keyCode
{
  return [[FBSimulatorHIDEvent_Keyboard alloc] initWithDirection:FBSimulatorHIDDirectionUp keyCode:keyCode];
}

#pragma mark Multiple Payload Events

+ (id<FBSimulatorHIDEventComposite>)eventWithEvents:(NSArray<id<FBSimulatorHIDEvent>> *)events
{
  return [[FBSimulatorHIDEvent_Composite alloc] initWithEvents:events];
}

+ (id<FBSimulatorHIDEventComposite>)tapAtX:(double)x y:(double)y
{
  return [self eventWithEvents:@[
    [self touchDownAtX:x y:y],
    [self touchUpAtX:x y:y],
  ]];
}

+ (id<FBSimulatorHIDEventComposite>)tapAtX:(double)x y:(double)y duration:(double)duration
{
  return [self eventWithEvents:@[
    [self touchDownAtX:x y:y],
    [self delay:duration],
    [self touchUpAtX:x y:y],
  ]];
}

+ (id<FBSimulatorHIDEventComposite>)shortButtonPress:(FBSimulatorHIDButton)button
{
  return [self eventWithEvents:@[
    [self buttonDown:button],
    [self buttonUp:button],
  ]];
}

+ (id<FBSimulatorHIDEventComposite>)shortKeyPress:(unsigned int)keyCode
{
  return [self eventWithEvents:@[
    [self keyDown:keyCode],
    [self keyUp:keyCode],
  ]];
}

+ (id<FBSimulatorHIDEvent>)shortKeyPressSequence:(NSArray<NSNumber *> *)sequence
{
  NSMutableArray<id<FBSimulatorHIDEventPayload>> *events = [NSMutableArray array];

  for (NSNumber *keyCode in sequence) {
    [events addObject:[self keyDown:[keyCode unsignedIntValue]]];
    [events addObject:[self keyUp:[keyCode unsignedIntValue]]];
  }

  return [self eventWithEvents:events];
}

+ (id<FBSimulatorHIDEvent>)swipe:(double)xStart yStart:(double)yStart xEnd:(double)xEnd yEnd:(double)yEnd delta:(double)delta duration:(double)duration
{
  NSMutableArray<id<FBSimulatorHIDEvent>> *events = [NSMutableArray array];
  double distance = sqrt(pow(yEnd - yStart, 2) + pow(xEnd - xStart, 2));
  if (delta <= 0.0) {
    delta = DEFAULT_SWIPE_DELTA;
  }
  int steps = (int)(distance / delta);

  double dx = (xEnd - xStart) / steps;
  double dy = (yEnd - yStart) / steps;

  double stepDelay = duration/(steps + 2);

  for (int i = 0 ; i <= steps ; ++i) {
    [events addObject:[self touchDownAtX:(xStart + dx * i) y:(yStart + dy * i)]];
    [events addObject:[self delay:stepDelay]];
  }
  // Add an additional touch down event at the end of the swipe to avoid intertial scroll on arm simulators.
  [events addObject:[self touchDownAtX:(xStart + dx * steps) y:(yStart + dy * steps)]];
  [events addObject:[self delay:stepDelay]];

  [events addObject:[self touchUpAtX:xEnd y:yEnd]];

  return [self eventWithEvents:events];
}

+ (id<FBSimulatorHIDEventDelay>)delay:(double)duration
{
  return [[FBSimulatorHIDEvent_Delay alloc] initWithDuration:duration];
}


@end
