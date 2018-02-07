/**
 * Copyright (c) 2017-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBLogicReporterAdapter.h"
#import <XCTestBootstrap/FBXCTestReporter.h>
#import <XCTestBootstrap/FBXCTestLogger.h>

@interface FBLogicReporterAdapter ()

@property (nonatomic, readonly) id<FBXCTestReporter> reporter;
@property (nonatomic, readonly) FBXCTestLogger *logger;

@end

@implementation FBLogicReporterAdapter

- (instancetype)initWithReporter:(id<FBXCTestReporter>)reporter
{
  self = [self init];
  if (!self) {
    return nil;
  }
  _reporter = reporter;
  _logger = [FBXCTestLogger defaultLoggerInDefaultDirectory];

  return self;
}

- (void)debuggerAttached
{
  [self.reporter debuggerAttached];
}

- (void)didBeginExecutingTestPlan
{
  [self.reporter didBeginExecutingTestPlan];
}

- (void)didFinishExecutingTestPlan
{
  [self.reporter didFinishExecutingTestPlan];
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
  NSError *error;
  NSDictionary<NSString *, id> *JSONEvent = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (error || ![JSONEvent isKindOfClass:[NSDictionary class]]) {
    [self.logger logFormat:@"[%@] Received invalid JSON: %@",
     NSStringFromClass(self.class),
     [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
    return;
  }
  NSString *eventName = JSONEvent[@"event"];
  id<FBXCTestReporter> reporter = self.reporter;

  if ([eventName isEqualToString:@"begin-test-suite"]) {
    NSString *suite = JSONEvent[@"suite"];
    NSString *startTime = JSONEvent[@"timestamp"];

    [reporter testSuite:suite didStartAt:startTime];
  } else if ([eventName isEqualToString:@"begin-test"]) {
    NSString *testClass = JSONEvent[@"className"];
    NSString *testName = JSONEvent[@"methodName"];

    [reporter testCaseDidStartForTestClass:testClass method:testName];
  } else if ([eventName isEqualToString:@"end-test"]) {
    [self handleEndTest:JSONEvent data:data];
  } else if ([eventName isEqualToString:@"end-test-suite"]) {
    NSDate *finishDate = [NSDate dateWithTimeIntervalSince1970:[JSONEvent[@"timestamp"] doubleValue]];
    NSInteger unexpected = [JSONEvent[@"unexpectedExceptionCount"] integerValue];
    FBTestManagerResultSummary *summary = [[FBTestManagerResultSummary alloc]
      initWithTestSuite:JSONEvent[@"suite"]
      finishTime:finishDate
      runCount:[JSONEvent[@"testCaseCount"] integerValue]
      failureCount:[JSONEvent[@"totalFailureCount"] integerValue]
      unexpected:unexpected
      testDuration:[JSONEvent[@"testDuration"] doubleValue]
      totalDuration:[JSONEvent[@"totalDuration"] doubleValue]];
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
  NSString *testClass = JSONEvent[@"className"];
  NSString *testName = JSONEvent[@"methodName"];
  NSString *result = JSONEvent[@"result"];
  NSTimeInterval duration = [JSONEvent[@"totalDuration"] doubleValue];

  if ([result isEqualToString:@"success"]) {
    [reporter testCaseDidFinishForTestClass:testClass method:testName withStatus:FBTestReportStatusPassed duration:duration];
  } else if ([[NSSet setWithArray:@[@"failure", @"error"]] containsObject:result]) {
    [self reportTestFailureForTestClass:testClass testName:testName endTestEvent:JSONEvent];
    [reporter testCaseDidFinishForTestClass:testClass method:testName withStatus:FBTestReportStatusFailed duration:duration];
  } else {
    // We don't know how to handle it, but an upstream reporter might.
    NSString *stringEvent = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [reporter handleExternalEvent:stringEvent];
  }
}

- (void)reportTestFailureForTestClass:(NSString *)testClass testName:(NSString *)testName endTestEvent:(NSDictionary *)JSONEvent
{
  NSDictionary *exception = [JSONEvent[@"exceptions"] lastObject];
  NSString *message = exception[@"reason"];
  NSString *file = exception[@"filePathInProject"];
  NSUInteger line = [exception[@"lineNumber"] unsignedIntegerValue];
  [self.reporter testCaseDidFailForTestClass:testClass method:testName withMessage:message file:file line:line];
}

@end
