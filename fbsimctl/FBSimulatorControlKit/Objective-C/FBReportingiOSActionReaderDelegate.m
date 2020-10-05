/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBReportingiOSActionReaderDelegate.h"

#import "FBUploadBuffer.h"

@interface FBReportingiOSActionReaderDelegate ()

@property (nonatomic, strong, readonly) id<FBEventReporter> reporter;

@end


@implementation FBReportingiOSActionReaderDelegate

- (instancetype)initWithReporter:(id<FBEventReporter>)reporter
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _reporter = reporter;

  return self;
}

#pragma mark Interpretation

- (NSString *)interpretAction:(id<FBiOSTargetFuture>)action eventType:(FBEventType)type
{
  FBEventName eventName;
  if ([[[action class] futureType] isEqualToString:FBiOSTargetFutureTypeApplicationLaunch]) {
    eventName = FBEventNameLaunch;
  } else if ([[[action class] futureType] isEqualToString:FBiOSTargetFutureTypeApplicationLaunch]) {
    eventName = FBEventNameLaunch;
  }else if ([[[action class] futureType] isEqualToString:FBiOSTargetFutureTypeApplicationLaunch]) {
    eventName = FBEventNameLaunchXCTest;
  } else {
    eventName = [[action class] futureType];
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

- (nullable NSString *)reader:(FBiOSActionReader *)reader willStartPerformingAction:(id<FBiOSTargetFuture>)action onTarget:(id<FBiOSTarget>)target
{
  return [self interpretAction:action eventType:FBEventTypeStarted];
}

- (nullable NSString *)reader:(FBiOSActionReader *)reader didProcessAction:(id<FBiOSTargetFuture>)action onTarget:(id<FBiOSTarget>)target
{
  return [self interpretAction:action eventType:FBEventTypeEnded];
}

- (nullable NSString *)reader:(FBiOSActionReader *)reader didFailToProcessAction:(id<FBiOSTargetFuture>)action onTarget:(id<FBiOSTarget>)target error:(NSError *)error
{
  id<FBEventReporterSubject> subject = [FBEventReporterSubject
    subjectWithName:FBEventNameFailure
    type:FBEventTypeDiscrete
    subject:[FBEventReporterSubject subjectWithString:error.localizedDescription]];

  return [self interpretSubject:subject];
}

- (void)readerDidFinishReading:(FBiOSActionReader *)reader
{

}

#pragma mark FBEventReporter Implementation

- (void)report:(id<FBEventReporterSubject>)subject
{
  [self.reporter report:subject];
}

- (void)addMetadata:(NSDictionary<NSString *, NSString *> *)metadata
{

}

- (id<FBEventInterpreter>)interpreter
{
  return self.reporter.interpreter;
}

- (id<FBDataConsumer>)consumer
{
  return self.reporter.consumer;
}

@synthesize metadata;

@end
