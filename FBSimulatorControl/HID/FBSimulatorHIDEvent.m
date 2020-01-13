/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorHIDEvent.h"

#import <FBControlCore/FBControlCore.h>

#import "FBSimulatorError.h"
#import "FBSimulatorHID.h"
#import "FBSimulator.h"
#import "FBSimulatorConnection.h"

FBiOSTargetFutureType const FBiOSTargetFutureTypeHID = @"hid";

static NSString *const KeyEventClass = @"class";
static NSString *const KeyDirection = @"direction";

static NSString *const EventClassStringComposite = @"composite";
static NSString *const EventClassStringTouch = @"touch";
static NSString *const EventClassStringButton = @"button";
static NSString *const EventClassStringKeyboard = @"keyboard";
static NSString *const EventClassStringDelay = @"delay";

const double DEFAULT_SWIPE_DELTA = 10.0;

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

- (FBFuture<NSNull *> *)performOnHID:(FBSimulatorHID *)hid
{
  return [self performEvents:self.events onHid:hid];
}

- (FBFuture<NSNull *> *)performEvents:(NSArray<FBSimulatorHIDEvent *> *)events onHid:(FBSimulatorHID *)hid
{
  if (events.count == 0) {
    return FBFuture.empty;
  }
  FBSimulatorHIDEvent *event = events.firstObject;
  NSArray<FBSimulatorHIDEvent *> *next = events.count == 1 ? @[] : [events subarrayWithRange:NSMakeRange(1, events.count - 1)];
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

- (FBFuture<NSNull *> *)performOnHID:(FBSimulatorHID *)hid
{
  return [hid sendTouchWithType:self.direction x:self.x y:self.y];
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
  return (NSUInteger) self.direction | ((NSUInteger) self.x ^ (NSUInteger) self.y);
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
- (FBFuture<NSNull *> *)performOnHID:(FBSimulatorHID *)hid
{
  return [hid sendButtonEventWithDirection:self.type button:self.button];
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

- (FBFuture<NSNull *> *)performOnHID:(FBSimulatorHID *)hid
{
  return [hid sendKeyboardEventWithDirection:self.direction keyCode:self.keyCode];
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
  return (NSUInteger) self.direction ^ (NSUInteger) self.keyCode;
}

@end

@interface FBSimulatorHIDEvent_Delay : FBSimulatorHIDEvent

@property (nonatomic, assign, readonly) double duration;

@end

@implementation FBSimulatorHIDEvent_Delay

static NSString *const KeyDuration = @"duration";

- (instancetype)initWithDuration:(double)duration
{
  self = [super init];
  if (!self) {
    return nil;
  }
  _duration = duration;
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
  if (![class isEqualToString:EventClassStringDelay]) {
    return [[FBSimulatorError
      describeFormat:@"Expected %@ to be %@", class, EventClassStringDelay]
      fail:error];
  }
  NSNumber *duration = json[KeyDuration];
  if (![duration isKindOfClass:NSNumber.class]) {
    return [[FBSimulatorError
      describeFormat:@"Expected %@ for %@ to be a Number", duration, KeyDuration]
      fail:error];
  }
  return [[self alloc] initWithDuration:duration.doubleValue];
}

- (id)jsonSerializableRepresentation
{
  return @{
    KeyDuration: @(self.duration),
    KeyEventClass: EventClassStringDelay,
  };
}

- (FBFuture<NSNull *> *)performOnHID:(FBSimulatorHID *)hid
{
  return [FBFuture futureWithDelay:self.duration future:FBFuture.empty];
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Delay for %f", self.duration];
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

#pragma mark Initializers

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

+ (instancetype)shortKeyPressSequence:(NSArray<NSNumber *> *)sequence
{
  NSMutableArray<FBSimulatorHIDEvent *> *events = [NSMutableArray array];

  for (id keyCode in sequence) {
    [events addObject:[self keyDown:[keyCode unsignedIntValue]]];
    [events addObject:[self keyUp:[keyCode unsignedIntValue]]];
  }

  return [self eventWithEvents:events];
}

+ (instancetype)swipe:(double)xStart yStart:(double)yStart xEnd:(double)xEnd yEnd:(double)yEnd delta:(double)delta duration:(double)duration
{
  NSMutableArray<FBSimulatorHIDEvent *> *events = [NSMutableArray array];
  double distance = sqrt(pow(yEnd - yStart, 2) + pow(xEnd - xStart, 2));
  if (delta <= 0.0) {
    delta = DEFAULT_SWIPE_DELTA;
  }
  int steps = (int)(distance / delta);

  double dx = (xEnd - xStart) / steps;
  double dy = (yEnd - yStart) / steps;

  double stepDelay = duration/(steps + 1);

  for (int i = 0 ; i <= steps ; ++i) {
    [events addObject:[self touchDownAtX:(xStart + dx * i) y:(yStart + dy * i)]];
    [events addObject:[self delay:stepDelay]];
  }

  [events addObject:[self touchUpAtX:xEnd y:yEnd]];

  return [self eventWithEvents:events];
}

+ (instancetype)delay:(double)duration
{
  return [[FBSimulatorHIDEvent_Delay alloc] initWithDuration:duration];
}

#pragma mark JSON

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

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone
{
  // All values are immutable.
  return self;
}

#pragma mark Public Methods

- (FBFuture<NSNull *> *)performOnHID:(FBSimulatorHID *)hid
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark Private Methods

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

#pragma mark FBiOSTargetFuture

+ (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeHID;
}

- (FBFuture<id<FBiOSTargetContinuation>> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBDataConsumer>)consumer reporter:(id<FBEventReporter>)reporter
{
  id<FBSimulatorLifecycleCommands> commands = (id<FBSimulatorLifecycleCommands>) target;
  if (![target conformsToProtocol:@protocol(FBSimulatorLifecycleCommands)]) {
    return [[FBSimulatorError
      describeFormat:@"%@ is not a Simulator", target]
      failFuture];
  }
  return [[[[commands
    connect]
    onQueue:target.workQueue fmap:^(FBSimulatorConnection *connection) {
      return [connection connectToHID];
    }]
    onQueue:target.workQueue fmap:^(FBSimulatorHID *hid) {
      return [self performOnHID:hid];
    }]
    mapReplace:FBiOSTargetContinuationDone(self.class.futureType)];
}

@end
