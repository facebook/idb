/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorHIDEvent.h"

#import <FBControlCore/FBControlCore.h>

#import "FBSimulatorError.h"
#import "FBSimulatorHID.h"
#import "FBSimulator.h"
#import "FBSimulatorConnection.h"

FBiOSTargetActionType const FBiOSTargetActionTypeHID = @"hid";

static NSString *const KeyEventClass = @"class";
static NSString *const KeyDirection = @"direction";

static NSString *const EventClassStringComposite = @"composite";
static NSString *const EventClassStringTouch = @"touch";
static NSString *const EventClassStringButton = @"button";
static NSString *const EventClassStringKeyboard = @"keyboard";

@interface FBSimulatorHIDEvent ()

+ (FBSimulatorHIDDirection)directionFromDirectionString:(NSString *)DirectionString;
+ (NSString *)directionStringFromDirection:(FBSimulatorHIDDirection)Direction;

@end

@interface FBSimulatorHIDEvent_Composite : FBSimulatorHIDEvent

@property (nonatomic, copy, readonly) NSArray<FBSimulatorHIDEvent *> *events;

@end

@implementation FBSimulatorHIDEvent_Composite

static NSString *const KeyEvents = @"events";

- (instancetype)initWithEvents:(NSArray<FBSimulatorHIDEvent *> *)events
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _events = events;
  return self;
}

+ (instancetype)inflateFromJSON:(id)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBSimulatorError
      describe:@"Expected an input of Dictionary<String, Object>"]
      fail:error];
  }
  NSString *class = json[KeyEventClass];
  if (![class isEqualToString:EventClassStringComposite]) {
    return [[FBSimulatorError
      describeFormat:@"Expected %@ to be %@", class, EventClassStringComposite]
      fail:error];
  }
  NSArray<NSDictionary *> *eventsJSON = json[KeyEvents];
  if (![FBCollectionInformation isArrayHeterogeneous:eventsJSON withClass:NSDictionary.class]) {
    return [[FBSimulatorError
      describeFormat:@"Expected %@ to be Array<Dictionary>", class]
      fail:error];
  }
  NSArray<FBSimulatorHIDEvent *> *events = [self eventsFromJSONEvents:eventsJSON error:error];
  if (!events) {
    return nil;
  }
  return [[self alloc] initWithEvents:events];
}

- (id)jsonSerializableRepresentation
{
  return @{
    KeyEvents: [FBSimulatorHIDEvent_Composite eventsJSONFromEvents:self.events],
    KeyEventClass: EventClassStringComposite,
  };
}

+ (nullable NSArray<FBSimulatorHIDEvent *> *)eventsFromJSONEvents:(NSArray<NSDictionary *> *)eventsJSON error:(NSError **)error
{
  NSMutableArray<FBSimulatorHIDEvent *> *events = [NSMutableArray arrayWithCapacity:eventsJSON.count];
  for (NSDictionary *json in eventsJSON) {
    FBSimulatorHIDEvent *event = [FBSimulatorHIDEvent inflateFromJSON:json error:error];
    if (!event) {
      return nil;
    }
    [events addObject:event];
  }
  return [events copy];
}

+ (NSArray<NSDictionary *> *)eventsJSONFromEvents:(NSArray<FBSimulatorHIDEvent *> *)events
{
  NSMutableArray<NSDictionary *> *eventsJSON = [NSMutableArray arrayWithCapacity:events.count];
  for (FBSimulatorHIDEvent *event in events) {
    [eventsJSON addObject:event.jsonSerializableRepresentation];
  }
  return [eventsJSON copy];
}

- (BOOL)performOnHID:(FBSimulatorHID *)hid error:(NSError **)error
{
  for (FBSimulatorHIDEvent *event in self.events) {
    if (![event performOnHID:hid error:error]) {
      return NO;
    }
  }
  return YES;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Composite %@", [FBCollectionInformation oneLineDescriptionFromArray:self.events]];
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

@interface FBSimulatorHIDEvent_Touch : FBSimulatorHIDEvent

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

+ (instancetype)inflateFromJSON:(id)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBSimulatorError
      describe:@"Expected an input of Dictionary<String, Object>"]
      fail:error];
  }
  NSString *class = json[KeyEventClass];
  if (![class isEqualToString:EventClassStringTouch]) {
    return [[FBSimulatorError
      describeFormat:@"Expected %@ to be %@", class, EventClassStringTouch]
      fail:error];
  }
  NSNumber *x = json[KeyX];
  if (![x isKindOfClass:NSNumber.class]) {
    return [[FBSimulatorError
      describeFormat:@"Expected %@ for %@ to be a Number", x, KeyX]
      fail:error];
  }
  NSNumber *y = json[KeyY];
  if (![y isKindOfClass:NSNumber.class]) {
    return [[FBSimulatorError
      describeFormat:@"Expected %@ for %@ to be a Number", x, KeyY]
      fail:error];
  }
  NSString *typeString = json[KeyDirection];
  if (![typeString isKindOfClass:NSString.class]) {
    return [[FBSimulatorError
      describeFormat:@"Expected %@ for %@ to be a String", typeString, KeyDirection]
      fail:error];
  }
  FBSimulatorHIDDirection type = [FBSimulatorHIDEvent directionFromDirectionString:typeString];
  if (type < 1) {
    return [[FBSimulatorError
      describeFormat:@"%@ is not a valid event type", typeString]
      fail:error];
  }
  return [[self alloc] initWithDirection:type x:x.unsignedIntegerValue y:y.unsignedIntegerValue];
}

- (id)jsonSerializableRepresentation
{
  return @{
    KeyX: @(self.x),
    KeyY: @(self.y),
    KeyDirection: [FBSimulatorHIDEvent directionStringFromDirection:self.direction],
    KeyEventClass: EventClassStringTouch,
  };
}

- (BOOL)performOnHID:(FBSimulatorHID *)hid error:(NSError **)error
{
  return [hid sendTouchWithType:self.direction x:self.x y:self.y error:error];
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Touch %@ at (%lu,%lu)",
    [FBSimulatorHIDEvent directionStringFromDirection:self.direction],
    (unsigned long)self.x,
    (unsigned long)self.y
  ];
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
  return self.direction | ((NSUInteger) self.x ^ (NSUInteger) self.y);
}

@end

static NSString *const KeyButton = @"button";
static NSString *const ButtonApplePay = @"apple_pay";
static NSString *const ButtonHomeButton = @"home";
static NSString *const ButtonLock = @"lock";
static NSString *const ButtonSideButton = @"side";
static NSString *const ButtonSiri = @"siri";

@interface FBSimulatorHIDEvent_Button : FBSimulatorHIDEvent

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

+ (instancetype)inflateFromJSON:(id)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSString.class]) {
    return [[FBSimulatorError
      describe:@"Expected an input of Dictionary<String, String>"]
      fail:error];
  }
  NSString *class = json[KeyEventClass];
  if (![class isEqualToString:EventClassStringButton]) {
    return [[FBSimulatorError
      describeFormat:@"Expected %@ to be %@", class, EventClassStringButton]
      fail:error];
  }
  NSString *buttonString = json[KeyButton];
  if (![buttonString isKindOfClass:NSString.class]) {
    return [[FBSimulatorError
      describeFormat:@"Expected %@ for %@ to be a String", buttonString, KeyButton]
      fail:error];
  }
  FBSimulatorHIDButton button = [self buttonFromButtonString:buttonString];
  if (button < 1) {
    return [[FBSimulatorError
      describeFormat:@"Button %@ for %@ is not a valid button type", buttonString, KeyButton]
      fail:error];
  }
  NSString *typeString = json[KeyDirection];
  if (![typeString isKindOfClass:NSString.class]) {
    return [[FBSimulatorError
      describeFormat:@"Expected %@ for %@ to be a String", typeString, KeyDirection]
      fail:error];
  }
  FBSimulatorHIDDirection type = [FBSimulatorHIDEvent directionFromDirectionString:typeString];
  if (type < 1) {
    return [[FBSimulatorError
      describeFormat:@"%@ is not a valid event type", typeString]
      fail:error];
  }
  return [[self alloc] initWithDirection:type button:button];
}

- (id)jsonSerializableRepresentation
{
  return @{
    KeyButton: [FBSimulatorHIDEvent_Button buttonStringFromButton:self.button],
    KeyDirection: [FBSimulatorHIDEvent directionStringFromDirection:self.type],
    KeyEventClass: EventClassStringButton,
  };
}
- (BOOL)performOnHID:(FBSimulatorHID *)hid error:(NSError **)error
{
  return [hid sendButtonEventWithDirection:self.type button:self.button error:error];
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Button %@ %@",
    [FBSimulatorHIDEvent_Button buttonStringFromButton:self.button],
    [FBSimulatorHIDEvent directionStringFromDirection:self.type]
  ];
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
  return self.type ^ self.button;
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

@interface FBSimulatorHIDEvent_Keyboard : FBSimulatorHIDEvent

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

+ (instancetype)inflateFromJSON:(id)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBSimulatorError
      describe:@"Expected an input of Dictionary<String, Object>"]
      fail:error];
  }
  NSString *class = json[KeyEventClass];
  if (![class isEqualToString:EventClassStringKeyboard]) {
    return [[FBSimulatorError
      describeFormat:@"Expected %@ to be %@", class, EventClassStringKeyboard]
      fail:error];
  }
  NSNumber *keycode = json[KeyKeycode];
  if (![keycode isKindOfClass:NSNumber.class]) {
    return [[FBSimulatorError
      describeFormat:@"Expected %@ for %@ to be a Number", keycode, KeyKeycode]
      fail:error];
  }
  NSString *typeString = json[KeyDirection];
  if (![typeString isKindOfClass:NSString.class]) {
    return [[FBSimulatorError
      describeFormat:@"Expected %@ for %@ to be a String", typeString, KeyDirection]
      fail:error];
  }
  FBSimulatorHIDDirection type = [FBSimulatorHIDEvent directionFromDirectionString:typeString];
  if (type < 1) {
    return [[FBSimulatorError
      describeFormat:@"%@ is not a valid event type", typeString]
      fail:error];
  }
  return [[self alloc] initWithDirection:type keyCode:keycode.unsignedIntValue];
}

- (id)jsonSerializableRepresentation
{
  return @{
    KeyKeycode: @(self.keyCode),
    KeyDirection: [FBSimulatorHIDEvent directionStringFromDirection:self.direction],
    KeyEventClass: EventClassStringKeyboard,
  };
}
- (BOOL)performOnHID:(FBSimulatorHID *)hid error:(NSError **)error
{
  return [hid sendKeyboardEventWithDirection:self.direction keyCode:self.keyCode error:error];
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Keyboard Code=%d %@",
    self.keyCode,
    [FBSimulatorHIDEvent directionStringFromDirection:self.direction]
  ];
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
  return self.direction ^ self.keyCode;
}

@end

@implementation FBSimulatorHIDEvent

+ (instancetype)eventWithEvents:(NSArray<FBSimulatorHIDEvent *> *)events
{
  return [[FBSimulatorHIDEvent_Composite alloc] initWithEvents:events];
}

+ (instancetype)touchDownAtX:(double)x y:(double)y
{
  return [[FBSimulatorHIDEvent_Touch alloc] initWithDirection:FBSimulatorHIDDirectionDown x:x y:y];
}

+ (instancetype)touchUpAtX:(double)x y:(double)y
{
  return [[FBSimulatorHIDEvent_Touch alloc] initWithDirection:FBSimulatorHIDDirectionUp x:x y:y];
}

+ (instancetype)buttonDown:(FBSimulatorHIDButton)button
{
  return [[FBSimulatorHIDEvent_Button alloc] initWithDirection:FBSimulatorHIDDirectionDown button:button];
}

+ (instancetype)buttonUp:(FBSimulatorHIDButton)button
{
  return [[FBSimulatorHIDEvent_Button alloc] initWithDirection:FBSimulatorHIDDirectionUp button:button];
}

+ (instancetype)keyDown:(unsigned int)keyCode
{
  return [[FBSimulatorHIDEvent_Keyboard alloc] initWithDirection:FBSimulatorHIDDirectionDown keyCode:keyCode];
}

+ (instancetype)keyUp:(unsigned int)keyCode
{
  return [[FBSimulatorHIDEvent_Keyboard alloc] initWithDirection:FBSimulatorHIDDirectionUp keyCode:keyCode];
}

+ (instancetype)tapAtX:(double)x y:(double)y
{
  return [self eventWithEvents:@[
    [self touchDownAtX:x y:y],
    [self touchUpAtX:x y:y],
  ]];
}

+ (instancetype)shortButtonPress:(FBSimulatorHIDButton)button
{
  return [self eventWithEvents:@[
    [self buttonDown:button],
    [self buttonUp:button],
  ]];
}

+ (instancetype)shortKeyPress:(unsigned int)keyCode
{
  return [self eventWithEvents:@[
    [self keyDown:keyCode],
    [self keyUp:keyCode],
  ]];
}

+ (instancetype)inflateFromJSON:(id)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBSimulatorError
      describe:@"Expected an input of Dictionary<String, Object>"]
      fail:error];
  }
  NSString *class = json[KeyEventClass];
  if (![class isKindOfClass:NSString.class]) {
    return [[FBSimulatorError
      describeFormat:@"%@ for %@ is not a String", class, KeyEventClass]
      fail:error];
  }
  if ([class isEqualToString:EventClassStringComposite]) {
    return [FBSimulatorHIDEvent_Composite inflateFromJSON:json error:error];
  }
  if ([class isEqualToString:EventClassStringTouch]) {
    return [FBSimulatorHIDEvent_Touch inflateFromJSON:json error:error];
  }
  if ([class isEqualToString:EventClassStringButton]) {
    return [FBSimulatorHIDEvent_Button inflateFromJSON:json error:error];
  }
  if ([class isEqualToString:EventClassStringKeyboard]) {
    return [FBSimulatorHIDEvent_Keyboard inflateFromJSON:json error:error];
  }
  return [[FBSimulatorError
    describeFormat:@"%@ is not one of %@ %@", class, EventClassStringComposite, EventClassStringTouch]
    fail:error];
}

- (id)jsonSerializableRepresentation
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (BOOL)performOnHID:(FBSimulatorHID *)hid error:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return NO;
}

- (id)copyWithZone:(NSZone *)zone
{
  // All values are immutable.
  return self;
}

static NSString *const DirectionDown = @"down";
static NSString *const DirectionUp = @"up";

+ (FBSimulatorHIDDirection)directionFromDirectionString:(NSString *)directionString
{
  if ([directionString isEqualToString:DirectionDown]) {
    return FBSimulatorHIDDirectionDown;
  }
  if ([directionString isEqualToString:DirectionUp]) {
    return FBSimulatorHIDDirectionUp;
  }
  return 0;
}

+ (NSString *)directionStringFromDirection:(FBSimulatorHIDDirection)direction
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

#pragma mark FBiOSTargetAction

+ (FBiOSTargetActionType)actionType
{
  return FBiOSTargetActionTypeHID;
}

- (BOOL)runWithTarget:(id<FBiOSTarget>)target delegate:(id<FBiOSTargetActionDelegate>)delegate error:(NSError **)error;
{
  if (![target isKindOfClass:FBSimulator.class]) {
    return [[FBSimulatorError
      describeFormat:@"%@ is not a Simulator", target]
      failBool:error];
  }
  FBSimulator *simulator = (FBSimulator *) target;
  FBSimulatorHID *hid = [[simulator connectWithError:error] connectToHID:error];
  if (!hid) {
    return NO;
  }
  return [self performOnHID:hid error:error];
}

@end
