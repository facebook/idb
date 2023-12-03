/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestReporterDouble.h"

@interface FBXCTestReporterDouble ()

@property (nonatomic, strong, readonly) NSMutableArray<NSString *> *mutableStartedSuites;
@property (nonatomic, strong, readonly) NSMutableArray<NSString *> *mutableEndedSuites;
@property (nonatomic, strong, readonly) NSMutableArray<NSArray<NSString *> *> *mutableStartedTestCases;
@property (nonatomic, strong, readonly) NSMutableArray<NSArray<NSString *> *> *mutablePassedTests;
@property (nonatomic, strong, readonly) NSMutableArray<NSArray<NSString *> *> *mutableFailedTests;
@property (nonatomic, strong, readonly) NSMutableArray<NSDictionary *> *mutableExternalEvents;
@property (nonatomic, assign, readwrite) BOOL printReportWasCalled;

@end

@implementation FBXCTestReporterDouble

#pragma mark Initializers

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _mutableStartedSuites = [NSMutableArray array];
  _mutableEndedSuites = [NSMutableArray array];
  _mutableStartedTestCases = [NSMutableArray array];
  _mutablePassedTests = [NSMutableArray array];
  _mutableFailedTests = [NSMutableArray array];
  _mutableExternalEvents = [NSMutableArray array];

  return self;
}

#pragma mark Methods for Validating

- (void)testCaseDidStartForTestClass:(NSString *)testClass method:(NSString *)method
{
  [self.mutableStartedTestCases addObject:@[testClass, method]];
}

- (BOOL)printReportWithError:(NSError **)error
{
  self.printReportWasCalled = YES;
  return YES;
}

- (void)handleExternalEvent:(NSString *)line
{
  NSError *error = nil;
  NSDictionary *event = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&error];
  if (event == nil) {
    return;
  }
  [self.mutableExternalEvents addObject:event];
}

#pragma mark Stubbed Methods

- (void)didBeginExecutingTestPlan
{

}

- (void)testSuite:(NSString *)testSuite didStartAt:(NSString *)startTime
{
  [self.mutableStartedSuites addObject:testSuite];
}

- (void)finishedWithSummary:(FBTestManagerResultSummary *)summary
{
  [self.mutableEndedSuites addObject:summary.testSuite];
}

- (void)didFinishExecutingTestPlan
{

}

- (void)testHadOutput:(NSString *)output
{

}

- (void)processWaitingForDebuggerWithProcessIdentifier:(pid_t)pid
{

}

- (void)didRecordVideoAtPath:(nonnull NSString *)videoRecordingPath
{

}

- (void)didSaveOSLogAtPath:(nonnull NSString *)osLogPath
{

}

- (void)didCopiedTestArtifact:(nonnull NSString *)testArtifactFilename toPath:(nonnull NSString *)path
{

}

- (void)processUnderTestDidExit
{

}

- (void)testCaseDidFinishForTestClass:(nonnull NSString *)testClass method:(nonnull NSString *)method withStatus:(FBTestReportStatus)status duration:(NSTimeInterval)duration logs:(nullable NSArray<NSString *> *)logs
{
  NSArray<NSString *> *pairs = @[testClass, method];

  switch (status) {
    case FBTestReportStatusPassed:
      [self.mutablePassedTests addObject:pairs];
      return;
    case FBTestReportStatusFailed:
      [self.mutableFailedTests addObject:pairs];
      return;
    default:
      return;
  }
}

- (void)didCrashDuringTest:(NSError *)error
{
  
}

- (void)testCaseDidFailForTestClass:(nonnull NSString *)testClass method:(nonnull NSString *)method exceptions:(nonnull NSArray<FBExceptionInfo *> *)exceptions {
  
}


#pragma mark Accessors

- (NSArray<NSString *> *)startedSuites
{
  return [self.mutableStartedSuites copy];
}

- (NSArray<NSString *> *)endedSuites
{
  return [self.mutableEndedSuites copy];
}

- (NSArray<NSArray<NSString *> *> *)startedTests
{
  return [self.mutableStartedTestCases copy];
}

- (NSArray<NSArray<NSString *> *> *)passedTests
{
  return [self.mutablePassedTests copy];
}

- (NSArray<NSArray<NSString *> *> *)failedTests
{
  return [self.mutableFailedTests copy];
}

- (NSArray<NSDictionary *> *)eventsWithName:(NSString *)name
{
  NSPredicate *predicate = [NSPredicate predicateWithBlock:^ BOOL (NSDictionary<NSString *, id> *event, id _) {
    return [event[@"event"] isEqualToString:name];
  }];
  return [self.mutableExternalEvents filteredArrayUsingPredicate:predicate];
}

@end
