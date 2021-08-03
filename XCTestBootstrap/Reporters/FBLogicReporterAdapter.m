/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBLogicReporterAdapter.h"
#import <XCTestBootstrap/FBXCTestReporter.h>
#import <XCTestBootstrap/FBXCTestLogger.h>

#import "FBXCTestConstants.h"

@interface FBLogicReporterAdapter ()

@property (nonatomic, readonly) id<FBXCTestReporter> reporter;
@property (nonatomic, readonly) FBXCTestLogger *logger;

@end

@implementation FBLogicReporterAdapter

- (instancetype)initWithReporter:(id<FBXCTestReporter>)reporter logger:(nullable id<FBControlCoreLogger>)logger
{
  self = [self init];
  if (!self) {
    return nil;
  }
  _reporter = reporter;
  _logger = [logger withName:@"FBLogicReporterAdapter"];

  return self;
}


- (void)didBeginExecutingTestPlan
{
  [self.reporter didBeginExecutingTestPlan];
}

- (void)didFinishExecutingTestPlan
{
  [self.reporter didFinishExecutingTestPlan];
  [self.reporter processUnderTestDidExit];
}

- (void)processWaitingForDebuggerWithProcessIdentifier:(pid_t)pid
{
  [self.reporter processWaitingForDebuggerWithProcessIdentifier:pid];
}

- (void)testHadOutput:(NSString *)output
{
  [self.reporter testHadOutput:output];
}

- (void)handleEventJSONData:(NSData *)data
{
  if (data.length == 0) {
    [self.logger log:@"Received zero-length JSON data"];
    return;
  }
  NSError *error;
  NSDictionary<NSString *, id> *JSONEvent = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (![JSONEvent isKindOfClass:[NSDictionary class]]) {
    [self.logger logFormat:@"Received invalid JSON: '%@' %@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], error];
    return;
  }

  NSString *eventName = JSONEvent[kReporter_Event_Key];
  id<FBXCTestReporter> reporter = self.reporter;
  if ([eventName isEqualToString:kReporter_Events_BeginTestSuite]) {
    NSString *suiteName = JSONEvent[kReporter_BeginTestSuite_SuiteKey];
    NSString *startTime = JSONEvent[kReporter_TimestampKey];
    [reporter testSuite:suiteName didStartAt:startTime];
  } else if ([eventName isEqualToString:kReporter_Events_BeginTest]) {
    NSString *className = JSONEvent[kReporter_BeginTest_ClassNameKey];
    NSString *methodName = JSONEvent[kReporter_BeginTest_MethodNameKey];
    [reporter testCaseDidStartForTestClass:className method:methodName];
  } else if ([eventName isEqualToString:kReporter_Events_EndTest]) {
    [self handleEndTest:JSONEvent data:data];
  } else if ([eventName isEqualToString:kReporter_Events_EndTestSuite]) {
    NSDate *finishDate = [NSDate dateWithTimeIntervalSince1970:[JSONEvent[kReporter_TimestampKey] doubleValue]];
    NSInteger unexpected = [JSONEvent[kReporter_EndTestSuite_UnexpectedExceptionCountKey] integerValue];
    FBTestManagerResultSummary *summary = [[FBTestManagerResultSummary alloc]
      initWithTestSuite:JSONEvent[kReporter_EndTestSuite_SuiteKey]
      finishTime:finishDate
      runCount:[JSONEvent[kReporter_EndTestSuite_TestCaseCountKey] integerValue]
      failureCount:[JSONEvent[kReporter_EndTestSuite_TotalFailureCountKey] integerValue]
      unexpected:unexpected
      testDuration:[JSONEvent[kReporter_EndTestSuite_TestDurationKey] doubleValue]
      totalDuration:[JSONEvent[kReporter_EndTest_TotalDurationKey] doubleValue]];
    [reporter finishedWithSummary:summary];
  } else {
    [self.logger logFormat:@"[%@] Unhandled event JSON: %@", NSStringFromClass(self.class), JSONEvent];
    //We don't know how to handle it, but an upstream reporter might.
    NSString *stringEvent = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [reporter handleExternalEvent:stringEvent];
  }
}

- (void)handleEndTest:(NSDictionary<NSString *, id> *)JSONEvent data:(NSData *)data
{
  id<FBXCTestReporter> reporter = self.reporter;
  NSString *testClass = JSONEvent[kReporter_EndTest_ClassNameKey];
  NSString *testName = JSONEvent[kReporter_EndTest_MethodNameKey];
  NSString *result = JSONEvent[kReporter_EndTest_ResultKey];
  NSTimeInterval duration = [JSONEvent[kReporter_EndTest_TotalDurationKey] doubleValue];

  if ([result isEqualToString:kReporter_EndTest_ResultValueSuccess]) {
    [reporter testCaseDidFinishForTestClass:testClass method:testName withStatus:FBTestReportStatusPassed duration:duration logs:nil];
  } else if ([[NSSet setWithArray:@[kReporter_EndTest_ResultValueFailure, kReporter_EndTest_ResultValueError]] containsObject:result]) {
    [self reportTestFailureForTestClass:testClass testName:testName endTestEvent:JSONEvent];
    [reporter testCaseDidFinishForTestClass:testClass method:testName withStatus:FBTestReportStatusFailed duration:duration logs:nil];
  } else {
    // We don't know how to handle it, but an upstream reporter might.
    NSString *stringEvent = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [reporter handleExternalEvent:stringEvent];
  }
}

- (void)reportTestFailureForTestClass:(NSString *)testClass testName:(NSString *)testName endTestEvent:(NSDictionary *)JSONEvent
{
  NSDictionary *exception = [JSONEvent[kReporter_EndTest_ExceptionsKey] lastObject];
  NSString *message = exception[kReporter_EndTest_Exception_ReasonKey];
  NSString *file = exception[kReporter_EndTest_Exception_FilePathInProjectKey];
  NSUInteger line = [exception[kReporter_EndTest_Exception_LineNumberKey] unsignedIntegerValue];
  [self.reporter testCaseDidFailForTestClass:testClass method:testName withMessage:message file:file line:line];
}

- (void)didCrashDuringTest:(NSError *)error
{
  if ([self.reporter respondsToSelector:@selector(didCrashDuringTest:)]) {
    [self.reporter didCrashDuringTest:error];
  }
}

@end
