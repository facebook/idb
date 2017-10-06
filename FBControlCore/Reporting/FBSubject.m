/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSubject.h"

#import "FBCollectionInformation.h"

@interface FBSingleItemSubject : FBEventReporterSubject

@end

@interface FBSimpleSubject : FBSingleItemSubject

- (instancetype)initWithName:(FBEventName)name type:(FBEventType)type subject:(FBEventReporterSubject *)subject;

@end

@interface FBControlCoreSubject : FBSingleItemSubject

- (instancetype)initWithValue:(id<FBJSONSerializable>)controlCoreValue;

@end

@interface FBiOSTargetSubject : FBSingleItemSubject

- (instancetype)initWithTarget:(id<FBiOSTarget>)target format:(FBiOSTargetFormat *)format;

@end

@interface FBiOSTargetWithSubject : FBSingleItemSubject

- (instancetype)initWithTargetSubject:(FBiOSTargetSubject *)targetSubject eventName:(FBEventName)eventName eventType:(FBEventType)eventType subject:(id<FBEventReporterSubject>)subject;

@end

@interface FBStringSubject : FBSingleItemSubject

- (instancetype)initWithString:(NSString *)string;

@end

@interface FBStringsSubject : FBSingleItemSubject

- (instancetype)initWithStrings:(NSArray<NSString *> *)strings;

@end

@interface FBLogSubject : FBSingleItemSubject

- (instancetype)initWithLogString:(NSString *)string level:(int)level;

@end

@interface FBCompositeSubject : FBEventReporterSubject

- (instancetype)initWithArray:(NSArray<id<FBEventReporterSubject>> *)eventReporterSubject;

@end

@implementation FBEventReporterSubject

#pragma mark Initializers

+ (instancetype)subjectWithName:(FBEventName)name type:(FBEventType)type subject:(id<FBEventReporterSubject>)subject
{
  return [[FBSimpleSubject alloc] initWithName:name type:type subject:subject];
}

+ (instancetype)subjectWithControlCoreValue:(id<FBJSONSerializable>)controlCoreValue
{
  return [[FBControlCoreSubject alloc] initWithValue:controlCoreValue];
}

+ (instancetype)subjectWithTarget:(id<FBiOSTarget>)target format:(FBiOSTargetFormat *)format
{
  return [[FBiOSTargetSubject alloc] initWithTarget:target format:format];
}

+ (instancetype)subjectWithTarget:(id<FBiOSTarget>)target format:(FBiOSTargetFormat *)format eventName:(FBEventName)eventName eventType:(FBEventType)eventType subject:(id<FBEventReporterSubject>)subject
{
  FBiOSTargetSubject *targetSubject = [[FBiOSTargetSubject alloc] initWithTarget:target format:format];
  return [[FBiOSTargetWithSubject alloc] initWithTargetSubject:targetSubject eventName:eventName eventType:eventType subject:subject];
}

+ (instancetype)subjectWithString:(NSString *)string
{
  return [[FBStringSubject alloc] initWithString:string];
}

+ (instancetype)subjectWithStrings:(NSArray<NSString *> *)strings
{
  return [[FBStringsSubject alloc] initWithStrings:strings];
}

+ (instancetype)logSubjectWithString:(NSString *)string level:(int)level
{
  return [[FBLogSubject alloc] initWithLogString:string level:level];
}

+ (instancetype)compositeSubjectWithArray:(NSArray<id<FBEventReporterSubject>> *)subjects
{
  return [[FBCompositeSubject alloc] initWithArray:subjects];
}

#pragma mark FBEventReporterSubject Protocol Implementation

- (id)jsonSerializableRepresentation
{
  return nil;
}

- (FBEventReporterSubject *)append:(FBEventReporterSubject *)other
{
  NSMutableArray *joined = [[NSMutableArray alloc] initWithArray:self.subSubjects];
  [joined addObject:other];

  switch (joined.count) {
    case 0:
      return [[FBCompositeSubject alloc] initWithArray:@[]];
    case 1:
      return [joined firstObject];
    default:
      return [[FBCompositeSubject alloc] initWithArray:joined];
  }
}

- (NSArray<id<FBEventReporterSubject>> *)subSubjects
{
  return  @[self];
}

@end

@implementation FBSingleItemSubject

- (NSArray<id<FBEventReporterSubject>> *)subSubjects
{
  return @[self];
}

@end

@interface FBSimpleSubject ()

@property (nonatomic, copy, readonly) FBEventName eventName;
@property (nonatomic, copy, readonly) FBEventType eventType;
@property (nonatomic, retain, readonly) FBEventReporterSubject *subject;

@end


@implementation FBSimpleSubject

- (instancetype)initWithName:(FBEventName)name
                        type:(FBEventType)type
                     subject:(FBEventReporterSubject *)subject
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _eventName = name;
  _eventType = type;
  _subject = subject;

  return self;
}

- (id)jsonSerializableRepresentation
{
  return @{
    FBJSONKeyEventType : self.eventType,
    FBJSONKeyTimestamp : [NSNumber numberWithInt:(int)[[NSDate date] timeIntervalSince1970]],
    FBJSONKeySubject   : [self.subject jsonSerializableRepresentation],
    FBJSONKeyEventName : self.eventName,
  };
}

- (NSString *)shortDescription
{
  if ([self.eventType isEqualToString:FBEventTypeDiscrete]) {
    return self.subject.description;
  }

  return [NSString stringWithFormat:@"%@ %@: %@",self.eventName, self.eventType, self.subject.description];
}

- (NSString *)description
{
  return [self shortDescription];
}

@end

@interface FBControlCoreSubject ()

@property (nonatomic, copy, readonly) id<FBJSONSerializable> value;

@end

@implementation FBControlCoreSubject

- (instancetype)initWithValue:(id<FBJSONSerializable>)controlCoreValue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _value = controlCoreValue;

  return self;
}

- (id)jsonSerializableRepresentation
{
  return self.value.jsonSerializableRepresentation;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"%@", self.value];
}

@end

@interface FBiOSTargetSubject ()

@property (nonatomic, copy, readonly) id<FBiOSTarget> target;
@property (nonatomic, copy, readonly) FBiOSTargetFormat *format;

@end

@implementation FBiOSTargetSubject

- (instancetype)initWithTarget:(id<FBiOSTarget>)target
                        format:(FBiOSTargetFormat *)format
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _target = target;
  _format = format;

  return self;
}

- (id)jsonSerializableRepresentation
{
  return [self.format extractFrom:self.target];
}

- (NSString *)description
{
  return [self.format format:self.target];
}

@end


@interface FBiOSTargetWithSubject ()

@property (nonatomic, copy, readonly) FBiOSTargetSubject *targetSubject;
@property (nonatomic, copy, readonly) FBEventName eventName;
@property (nonatomic, copy, readonly) FBEventType eventType;
@property (nonatomic, retain, readonly) FBEventReporterSubject *subject;
@property (nonatomic, retain, readonly) NSDate *timestamp;

@end

@implementation FBiOSTargetWithSubject

- (instancetype)initWithTargetSubject:(FBiOSTargetSubject *)targetSubject
                            eventName:(FBEventName)eventName
                            eventType:(FBEventType)eventType
                              subject:(FBEventReporterSubject *)subject
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _targetSubject = targetSubject;
  _eventName = eventName;
  _eventType = eventType;
  _subject = subject;
  _timestamp = [NSDate date];

  return self;
}

- (id)jsonSerializableRepresentation
{
  return @{
    FBJSONKeyEventName : self.eventName,
    FBJSONKeyEventType : self.eventType,
    FBJSONKeyTarget    : [self.targetSubject jsonSerializableRepresentation],
    FBJSONKeySubject   : [self.subject jsonSerializableRepresentation],
    FBJSONKeyTimestamp : [NSNumber numberWithInt:(int)[self.timestamp timeIntervalSince1970]],
  };
}

- (NSString *)description
{
  if ([self.eventType isEqualToString:FBEventTypeDiscrete]) {
    return [NSString stringWithFormat:@"%@: %@: %@", self.targetSubject, self.eventName, self.subject.description];
  }

  return @"";
}

@end

@interface FBLogSubject ()

@property (nonatomic, copy, readonly) NSString *logString;
@property (nonatomic, assign, readonly) int level;

@end

@implementation FBLogSubject

- (instancetype)initWithLogString:(NSString *)string level:(int)level
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _logString = string;
  _level = level;

  return self;
}

- (id)jsonSerializableRepresentation
{
  return @{
    FBJSONKeyEventType : FBEventTypeDiscrete,
    FBJSONKeyTimestamp : [NSNumber numberWithInt:(int)[[NSDate date] timeIntervalSince1970]],
    FBJSONKeyLevel     : [self levelString],
    FBJSONKeySubject   : self.logString,
    FBJSONKeyEventName : FBEventNameLog,
  };
}

- (NSString *)description
{
  return self.logString;
}

- (NSString *)levelString
{
  switch (self.level) {
    case ASL_LEVEL_DEBUG:
      return @"debug";
    case ASL_LEVEL_ERR:
      return @"error";
    case ASL_LEVEL_INFO:
      return @"into";
    default:
      return @"unknown";
  }
}

@end

@interface FBCompositeSubject ()

@property (nonatomic, copy, readonly) NSArray<id<FBEventReporterSubject>> *subjects;

@end

@implementation FBCompositeSubject

- (instancetype)initWithArray:(NSArray<FBEventReporterSubject *> *)subjects
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _subjects = subjects;

  return self;
}

- (id)jsonSerializableRepresentation
{
  NSMutableArray *output = [[NSMutableArray alloc] initWithCapacity:self.subjects.count];

  for (id eventReporterSubject in self.subjects) {
    [output addObject:[eventReporterSubject jsonSerializableRepresentation]];
  }

  return output;
}

- (NSArray<FBEventReporterSubject *> *)subSubjects
{
  return self.subjects;
}

- (NSString *)description
{
  NSMutableArray *descriptions = [[NSMutableArray alloc] initWithCapacity:self.subjects.count];
  for (id item in self.subjects) {
    [descriptions addObject:[item description]];
  }

  NSString *base = [descriptions componentsJoinedByString:@","];

  return [NSString stringWithFormat:@"[%@]", base];
}

@end

@interface FBStringSubject ()

@property (nonatomic, copy, readonly) NSString *string;

@end

@implementation FBStringSubject

- (instancetype)initWithString:(NSString *)string
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _string = string;

  return self;
}

- (id)jsonSerializableRepresentation
{
  return self.string;
}

- (NSString *)description
{
  return self.string;
}

@end

@interface FBStringsSubject ()

@property (nonatomic, copy, readonly) NSArray<NSString *> *strings;

@end

@implementation FBStringsSubject

- (instancetype)initWithStrings:(NSArray<NSString *> *)strings
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _strings = strings;

  return self;
}

- (id)jsonSerializableRepresentation
{
  return self.strings;
}

- (NSString *)description
{
  return [self.strings componentsJoinedByString:@"\n"];
}

@end
