/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBEventReporterSubject.h"

#import "FBCollectionInformation.h"

FBEventType const FBEventTypeStarted = @"started";
FBEventType const FBEventTypeEnded = @"ended";
FBEventType const FBEventTypeDiscrete = @"discrete";
FBEventType const FBEventTypeSuccess = @"success";
FBEventType const FBEventTypeFailure = @"failure";

@implementation FBEventReporterSubject

@synthesize eventName = _eventName;
@synthesize eventType = _eventType;
@synthesize arguments = _arguments;
@synthesize duration = _duration;
@synthesize message = _message;
@synthesize size = _size;
@synthesize reportNativeSwiftMethodCall = _reportNativeSwiftMethodCall;

#pragma mark Initializers

+ (instancetype)subjectForEvent:(NSString *)eventName
{
  return [[FBEventReporterSubject alloc] initWithEventName:eventName eventType:FBEventTypeDiscrete arguments:nil duration:nil size:nil message:nil reportNativeSwiftMethodCall:NO];
}

+ (instancetype)subjectForStartedCall:(NSString *)call arguments:(NSArray<NSString *> *)arguments reportNativeSwiftMethodCall:(BOOL)reportNativeSwiftMethodCall
{
  return [[FBEventReporterSubject alloc] initWithEventName:call eventType:FBEventTypeStarted arguments:arguments duration:nil size:nil message:nil reportNativeSwiftMethodCall:reportNativeSwiftMethodCall];
}

+ (instancetype)subjectForSuccessfulCall:(NSString *)call duration:(NSTimeInterval)duration size:(NSNumber *)size arguments:(NSArray<NSString *> *)arguments reportNativeSwiftMethodCall:(BOOL)reportNativeSwiftMethodCall
{
  return [[FBEventReporterSubject alloc] initWithEventName:call eventType:FBEventTypeSuccess arguments:arguments duration:[self durationMilliseconds:duration] size:size message:nil reportNativeSwiftMethodCall:reportNativeSwiftMethodCall];
}

+ (instancetype)subjectForFailingCall:(NSString *)call duration:(NSTimeInterval)duration message:(NSString *)message size:(NSNumber *)size arguments:(NSArray<NSString *> *)arguments reportNativeSwiftMethodCall:(BOOL)reportNativeSwiftMethodCall
{
  return [[FBEventReporterSubject alloc] initWithEventName:call eventType:FBEventTypeFailure arguments:arguments duration:[self durationMilliseconds:duration] size:size message:message reportNativeSwiftMethodCall:reportNativeSwiftMethodCall];
}

+ (NSNumber *)durationMilliseconds:(NSTimeInterval)timeInterval
{
  NSUInteger milliseconds = (NSUInteger) (timeInterval * 1000);
  return @(milliseconds);
}

- (instancetype)initWithEventName:(NSString *)eventName eventType:(FBEventType)eventType arguments:(NSArray<NSString *> *)arguments duration:(NSNumber *)duration size:(NSNumber *)size message:(NSString *)message reportNativeSwiftMethodCall:(BOOL)reportNativeSwiftMethodCall
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _eventName = eventName;
  _eventType = eventType;
  _arguments = arguments;
  _duration = duration;
  _size = size;
  _message = message;
  _reportNativeSwiftMethodCall = reportNativeSwiftMethodCall;

  return self;
}

@end
