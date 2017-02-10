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

static NSString *const FBSimulatorEventKeyClass = @"class";
static NSString *const FBSimulatorHIDEventKeyType = @"type";

static NSString *const FBSimulatorEventClassStringComposite = @"composite";
static NSString *const FBSimulatorEventClassStringTouch = @"touch";
static NSString *const FBSimulatorEventClassStringButton = @"button";

@interface FBSimulatorHIDEvent ()

+ (FBSimulatorHIDEventType)eventTypeForEventTypeString:(NSString *)eventTypeString;
+ (NSString *)eventTypeStringFromEventType:(FBSimulatorHIDEventType)eventType;

@end

@interface FBSimulatorHIDEvent_Composite : FBSimulatorHIDEvent

@property (nonatomic, copy, readonly) NSArray<FBSimulatorHIDEvent *> *events;

@end

@implementation FBSimulatorHIDEvent_Composite

static NSString *const FBSimulatorEventKeyEvents = @"events";

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
  NSString *class = json[FBSimulatorEventKeyClass];
  if (![class isEqualToString:FBSimulatorEventClassStringComposite]) {
    return [[FBSimulatorError
      describeFormat:@"Expected %@ to be %@", class, FBSimulatorEventClassStringComposite]
      fail:error];
  }
  NSArray<NSDictionary *> *eventsJSON = json[FBSimulatorEventKeyEvents];
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
    FBSimulatorEventKeyEvents: [FBSimulatorHIDEvent_Composite eventsJSONFromEvents:self.events],
    FBSimulatorEventKeyClass: FBSimulatorEventClassStringComposite,
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

@property (nonatomic, assign, readonly) FBSimulatorHIDEventType type;
@property (nonatomic, assign, readonly) double x;
@property (nonatomic, assign, readonly) double y;

@end

@implementation FBSimulatorHIDEvent_Touch

static NSString *const FBSimulatorHIDEventKeyX = @"x";
static NSString *const FBSimulatorHIDEventKeyY = @"y";

- (instancetype)initWithEventType:(FBSimulatorHIDEventType)type x:(double)x y:(double)y
{
  self = [super init];
  if (!self) {
    return nil;
  }
  _type = type;
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
  NSString *class = json[FBSimulatorEventKeyClass];
  if (![class isEqualToString:FBSimulatorEventClassStringTouch]) {
    return [[FBSimulatorError
      describeFormat:@"Expected %@ to be %@", class, FBSimulatorEventClassStringTouch]
      fail:error];
  }
  NSNumber *x = json[FBSimulatorHIDEventKeyX];
  if (![x isKindOfClass:NSNumber.class]) {
    return [[FBSimulatorError
      describeFormat:@"Expected %@ for %@ to be a Number", x, FBSimulatorHIDEventKeyX]
      fail:error];
  }
  NSNumber *y = json[FBSimulatorHIDEventKeyY];
  if (![y isKindOfClass:NSNumber.class]) {
    return [[FBSimulatorError
      describeFormat:@"Expected %@ for %@ to be a Number", x, FBSimulatorHIDEventKeyY]
      fail:error];
  }
  NSString *typeString = json[FBSimulatorHIDEventKeyType];
  if (![typeString isKindOfClass:NSString.class]) {
    return [[FBSimulatorError
      describeFormat:@"Expected %@ for %@ to be a String", typeString, FBSimulatorHIDEventKeyType]
      fail:error];
  }
  FBSimulatorHIDEventType type = [FBSimulatorHIDEvent eventTypeForEventTypeString:typeString];
  if (type < 1) {
    return [[FBSimulatorError
      describeFormat:@"%@ is not a valid event type", typeString]
      fail:error];
  }
  return [[self alloc] initWithEventType:type x:x.unsignedIntegerValue y:y.unsignedIntegerValue];
}

- (id)jsonSerializableRepresentation
{
  return @{
    FBSimulatorHIDEventKeyX: @(self.x),
    FBSimulatorHIDEventKeyY: @(self.y),
    FBSimulatorHIDEventKeyType: [FBSimulatorHIDEvent eventTypeStringFromEventType:self.type],
    FBSimulatorEventKeyClass: FBSimulatorEventClassStringTouch,
  };
}

- (BOOL)performOnHID:(FBSimulatorHID *)hid error:(NSError **)error
{
  return [hid sendTouchWithType:self.type x:self.x y:self.y error:error];
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Touch %@ at (%lu,%lu)",
    [FBSimulatorHIDEvent eventTypeStringFromEventType:self.type],
    (unsigned long)self.x,
    (unsigned long)self.y
  ];
}

- (BOOL)isEqual:(FBSimulatorHIDEvent_Touch *)event
{
  if (![event isKindOfClass:self.class]) {
    return NO;
  }
  return self.type == event.type && self.x == event.x && self.y == event.y;
}

- (NSUInteger)hash
{
  return self.type | ((NSUInteger) self.x ^ (NSUInteger) self.y);
}

@end

static NSString *const FBSimulatorHIDEventKeyButton = @"button";
static NSString *const FBSimulatorHIDButtonStringApplePay = @"apple_pay";
static NSString *const FBSimulatorHIDButtonStringHomeButton = @"home";
static NSString *const FBSimulatorHIDButtonStringLock = @"lock";
static NSString *const FBSimulatorHIDButtonStringSideButton = @"side";
static NSString *const FBSimulatorHIDButtonStringSiri = @"siri";

@interface FBSimulatorHIDEvent_Button : FBSimulatorHIDEvent

@property (nonatomic, assign, readonly) FBSimulatorHIDEventType type;
@property (nonatomic, assign, readonly) FBSimulatorHIDButton button;

@end

@implementation FBSimulatorHIDEvent_Button

- (instancetype)initWithEventType:(FBSimulatorHIDEventType)type button:(FBSimulatorHIDButton)button
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
  NSString *class = json[FBSimulatorEventKeyClass];
  if (![class isEqualToString:FBSimulatorEventClassStringButton]) {
    return [[FBSimulatorError
      describeFormat:@"Expected %@ to be %@", class, FBSimulatorEventClassStringButton]
      fail:error];
  }
  NSString *buttonString = json[FBSimulatorHIDEventKeyButton];
  if (![buttonString isKindOfClass:NSString.class]) {
    return [[FBSimulatorError
      describeFormat:@"Expected %@ for %@ to be a String", buttonString, FBSimulatorHIDEventKeyButton]
      fail:error];
  }
  FBSimulatorHIDButton button = [self buttonFromButtonString:buttonString];
  if (button < 1) {
    return [[FBSimulatorError
      describeFormat:@"Button %@ for %@ is not a valid button type", buttonString, FBSimulatorHIDEventKeyButton]
      fail:error];
  }
  NSString *typeString = json[FBSimulatorHIDEventKeyType];
  if (![typeString isKindOfClass:NSString.class]) {
    return [[FBSimulatorError
      describeFormat:@"Expected %@ for %@ to be a String", typeString, FBSimulatorHIDEventKeyType]
      fail:error];
  }
  FBSimulatorHIDEventType type = [FBSimulatorHIDEvent eventTypeForEventTypeString:typeString];
  if (type < 1) {
    return [[FBSimulatorError
      describeFormat:@"%@ is not a valid event type", typeString]
      fail:error];
  }
  return [[self alloc] initWithEventType:type button:button];
}

- (id)jsonSerializableRepresentation
{
  return @{
    FBSimulatorHIDEventKeyButton: [FBSimulatorHIDEvent_Button buttonStringFromButton:self.button],
    FBSimulatorHIDEventKeyType: [FBSimulatorHIDEvent eventTypeStringFromEventType:self.type],
    FBSimulatorEventKeyClass: FBSimulatorEventClassStringButton,
  };
}
- (BOOL)performOnHID:(FBSimulatorHID *)hid error:(NSError **)error
{
  return [hid sendButtonEventWithType:self.type button:self.button error:error];
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Button %@ %@",
    [FBSimulatorHIDEvent_Button buttonStringFromButton:self.button],
    [FBSimulatorHIDEvent eventTypeStringFromEventType:self.type]
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
      return FBSimulatorHIDButtonStringApplePay;
    case FBSimulatorHIDButtonHomeButton:
      return FBSimulatorHIDButtonStringHomeButton;
    case FBSimulatorHIDButtonLock:
      return FBSimulatorHIDButtonStringLock;
    case FBSimulatorHIDButtonSideButton:
      return FBSimulatorHIDButtonStringSideButton;
    case FBSimulatorHIDButtonSiri:
      return FBSimulatorHIDButtonStringSiri;
    default:
      return nil;
  }
}

+ (FBSimulatorHIDButton)buttonFromButtonString:(NSString *)buttonString
{
  if ([buttonString isEqualToString:FBSimulatorHIDButtonStringApplePay]) {
    return FBSimulatorHIDButtonApplePay;
  }
  if ([buttonString isEqualToString:FBSimulatorHIDButtonStringHomeButton]) {
    return FBSimulatorHIDButtonHomeButton;
  }
  if ([buttonString isEqualToString:FBSimulatorHIDButtonStringSideButton]) {
    return FBSimulatorHIDButtonSideButton;
  }
  if ([buttonString isEqualToString:FBSimulatorHIDButtonStringSiri]) {
    return FBSimulatorHIDButtonSiri;
  }
  if ([buttonString isEqualToString:FBSimulatorHIDButtonStringLock]) {
    return FBSimulatorHIDButtonLock;
  }
  return 0;
}

@end

@implementation FBSimulatorHIDEvent

+ (instancetype)eventWithEvents:(NSArray<FBSimulatorHIDEvent *> *)events
{
  return [[FBSimulatorHIDEvent_Composite alloc] initWithEvents:events];
}

+ (instancetype)touchDownAtX:(double)x y:(double)y
{
  return [[FBSimulatorHIDEvent_Touch alloc] initWithEventType:FBSimulatorHIDEventTypeDown x:x y:y];
}

+ (instancetype)touchUpAtX:(double)x y:(double)y
{
  return [[FBSimulatorHIDEvent_Touch alloc] initWithEventType:FBSimulatorHIDEventTypeUp x:x y:y];
}

+ (instancetype)buttonDown:(FBSimulatorHIDButton)button
{
  return [[FBSimulatorHIDEvent_Button alloc] initWithEventType:FBSimulatorHIDEventTypeDown button:button];
}

+ (instancetype)buttonUp:(FBSimulatorHIDButton)button
{
  return [[FBSimulatorHIDEvent_Button alloc] initWithEventType:FBSimulatorHIDEventTypeUp button:button];
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

+ (instancetype)inflateFromJSON:(id)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBSimulatorError
      describe:@"Expected an input of Dictionary<String, Object>"]
      fail:error];
  }
  NSString *class = json[FBSimulatorEventKeyClass];
  if (![class isKindOfClass:NSString.class]) {
    return [[FBSimulatorError
      describeFormat:@"%@ for %@ is not a String", class, FBSimulatorEventKeyClass]
      fail:error];
  }
  if ([class isEqualToString:FBSimulatorEventClassStringComposite]) {
    return [FBSimulatorHIDEvent_Composite inflateFromJSON:json error:error];
  }
  if ([class isEqualToString:FBSimulatorEventClassStringTouch]) {
    return [FBSimulatorHIDEvent_Touch inflateFromJSON:json error:error];
  }
  if ([class isEqualToString:FBSimulatorEventClassStringButton]) {
    return [FBSimulatorHIDEvent_Button inflateFromJSON:json error:error];
  }
  return [[FBSimulatorError
    describeFormat:@"%@ is not one of %@ %@", class, FBSimulatorEventClassStringComposite, FBSimulatorEventClassStringTouch]
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


static NSString *const FBSimulatorEventTypeStringDown = @"down";
static NSString *const FBSimulatorEventTypeStringUp = @"up";

+ (FBSimulatorHIDEventType)eventTypeForEventTypeString:(NSString *)eventTypeString
{
  if ([eventTypeString isEqualToString:FBSimulatorEventTypeStringDown]) {
    return FBSimulatorHIDEventTypeDown;
  }
  if ([eventTypeString isEqualToString:FBSimulatorEventTypeStringUp]) {
    return FBSimulatorHIDEventTypeUp;
  }
  return 0;
}

+ (NSString *)eventTypeStringFromEventType:(FBSimulatorHIDEventType)eventType
{
  switch (eventType) {
    case FBSimulatorHIDEventTypeDown:
      return FBSimulatorEventTypeStringDown;
    case FBSimulatorHIDEventTypeUp:
      return FBSimulatorEventTypeStringUp;
    default:
      return nil;
  }
}

@end
