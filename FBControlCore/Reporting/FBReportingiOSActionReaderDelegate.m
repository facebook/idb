/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBReportingiOSActionReaderDelegate.h"
#import "FBSubject.h"
#import "FBJSONEnums.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@interface FBReportingiOSActionReaderDelegate ()

@property (nonatomic, retain, readonly) id<FBiOSActionReaderDelegate> delegate;
@property (nonatomic, retain, readonly) id<FBEventInterpreter> interpreter;

@end


@implementation FBReportingiOSActionReaderDelegate

- (instancetype)initWithDelegate:(id<FBiOSActionReaderDelegate>)delegate interpreter:(id<FBEventInterpreter>)interpreter
{
  self = [super init];

  if (!self) {
    return nil;
  }

  _delegate = delegate;
  _interpreter = interpreter;

  return self;
}

#pragma mark Interpretation

- (NSString *)interpretAction:(id<FBiOSTargetAction>)action eventType:(FBEventType)type
{
  FBEventName eventName;
  if ([[[action class] actionType] isEqualToString:FBiOSTargetActionTypeApplicationLaunch]) {
    eventName = FBEventNameLaunch;
  } else if ([[[action class] actionType] isEqualToString:FBiOSTargetActionTypeApplicationLaunch]) {
    eventName = FBEventNameLaunch;
  }else if ([[[action class] actionType] isEqualToString:FBiOSTargetActionTypeApplicationLaunch]) {
    eventName = FBEventNameLaunchXCTest;
  } else {
    eventName = [[action class] actionType];
  }

  id<FBEventReporterSubject> subject = [FBEventReporterSubject
    subjectWithName:eventName
    type:type
    subject:[FBEventReporterSubject subjectWithControlCoreValue:action]];
  return [self interpretSubject:subject];
}

- (NSString *)interpretSubject:(FBEventReporterSubject *)subject
{
  return [self.interpreter interpret:subject];
}

#pragma mark Forwarding

- (id)forwardingTargetForSelector:(SEL)aSelector
{
  if ([self.delegate respondsToSelector:aSelector]) {
    return self.delegate;
  }

  return [super forwardingTargetForSelector:aSelector];
}

#pragma mark FBiOSActionReaderDelegate methods

- (nullable NSString *)reader:(FBiOSActionReader *)reader failedToInterpretInput:(NSString *)input error:(NSError *)error
{
  NSString *message = [NSString stringWithFormat:@"%@. input: %@", error.localizedDescription, input];
  id<FBEventReporterSubject> subject = [FBEventReporterSubject
    subjectWithName:FBEventNameFailure
    type:FBEventTypeDiscrete
    subject:[FBEventReporterSubject subjectWithString:message]];

  return [self interpretSubject:subject];
}

- (nullable NSString *)reader:(FBiOSActionReader *)reader willStartReadingUpload:(FBUploadHeader *)header
{
  return [self interpretAction:header eventType:FBEventTypeStarted];
}

- (nullable NSString *)reader:(FBiOSActionReader *)reader didFinishUpload:(FBUploadedDestination *)destination
{
  return [self interpretAction:destination eventType:FBEventTypeEnded];
}

- (nullable NSString *)reader:(FBiOSActionReader *)reader willStartPerformingAction:(id<FBiOSTargetAction>)action onTarget:(id<FBiOSTarget>)target
{
  return [self interpretAction:action eventType:FBEventTypeStarted];
}

- (nullable NSString *)reader:(FBiOSActionReader *)reader didProcessAction:(id<FBiOSTargetAction>)action onTarget:(id<FBiOSTarget>)target
{
  return [self interpretAction:action eventType:FBEventTypeEnded];
}

- (nullable NSString *)reader:(FBiOSActionReader *)reader didFailToProcessAction:(id<FBiOSTargetAction>)action onTarget:(id<FBiOSTarget>)target error:(NSError *)error
{
  id<FBEventReporterSubject> subject = [FBEventReporterSubject
    subjectWithName:FBEventNameFailure
    type:FBEventTypeDiscrete
    subject:[FBEventReporterSubject subjectWithString:error.localizedDescription]];

  return [self interpretSubject:subject];
}

@end

#pragma clang diagnostic pop
