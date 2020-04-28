/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>
#import <XCTestBootstrap/FBLogicReporterAdapter.h>
#import <XCTestBootstrap/FBXCTestReporter.h>
#import <XCTestBootstrap/FBTestManagerResultSummary.h>
#import <OCMock/OCMock.h>

@interface FBLogicReporterAdapterTests : XCTestCase

@property (nonatomic, strong, nullable, readwrite) FBLogicReporterAdapter *adapter;
@property (nonatomic, strong, nullable, readwrite) OCMockObject *reporterMock;

@end

static NSDictionary *beginTestSuiteDict() {
  return @{
    @"event": @"begin-test-suite",
    @"suite": @"NARANJA",
    @"timestamp": @"1970",
  };
}

static NSDictionary *testEventDict() {
  return @{
    @"className": @"OmniClass",
    @"methodName": @"theMethod:toRule:themAll:",
  };
}

static FBTestManagerResultSummary *summaryFromDictionary(NSDictionary *JSONEvent) {
  NSDate *finishDate = [NSDate dateWithTimeIntervalSince1970:[JSONEvent[@"timestamp"] doubleValue]];
  NSInteger unexpected = [JSONEvent[@"unexpectedExceptionCount"] integerValue];
  return [[FBTestManagerResultSummary alloc]
    initWithTestSuite:JSONEvent[@"suite"]
    finishTime:finishDate
    runCount:[JSONEvent[@"testCaseCount"] integerValue]
    failureCount:[JSONEvent[@"totalFailureCount"] integerValue]
    unexpected:unexpected
    testDuration:[JSONEvent[@"testDuration"] doubleValue]
    totalDuration:[JSONEvent[@"totalDuration"] doubleValue]];
}

@implementation FBLogicReporterAdapterTests

- (void)setUp
{
  [super setUp];
  self.reporterMock = [OCMockObject mockForProtocol:@protocol(FBXCTestReporter)];
  self.adapter = [[FBLogicReporterAdapter alloc] initWithReporter:(id)self.reporterMock logger:nil];
}

- (void)test_LogicReporter_testSuiteDidStart
{
  OCMockObject *mock = self.reporterMock;
  NSData *data = [NSJSONSerialization dataWithJSONObject:beginTestSuiteDict() options:0 error:NULL];
  [[mock expect] testSuite:@"NARANJA" didStartAt:@"1970"];

  [self.adapter handleEventJSONData:data];
  [mock verify];
}

- (void)test_LogicReporter_testCaseDidStart
{
  OCMockObject *mock = self.reporterMock;
  NSMutableDictionary *event = [testEventDict() mutableCopy];
  event[@"event"] = @"begin-test";

  [[mock expect] testCaseDidStartForTestClass:event[@"className"] method:event[@"methodName"]];

  NSData *data = [NSJSONSerialization dataWithJSONObject:event options:0 error:NULL];
  [self.adapter handleEventJSONData:data];
  [mock verify];
}

- (void)test_LogicReporter_testCaseDidFail_fromFailure
{
  OCMockObject *mock = self.reporterMock;
  NSMutableDictionary *event = [testEventDict() mutableCopy];
  NSTimeInterval duration = 0.0050642;
  event[@"totalDuration"] = @(duration);
  event[@"event"] = @"end-test";
  event[@"result"] = @"failure";

  NSString *message = @"The message to win all messages";
  NSUInteger line = 969;
  NSString *file = @"dasLiebstenFeile";
  event[@"exceptions"] = @[@{
    @"reason": message,
    @"lineNumber": @(line),
    @"filePathInProject": file,
  }];
  [[mock expect] testCaseDidFailForTestClass:event[@"className"] method:event[@"methodName"] withMessage:message file:file line:line];
  [[mock expect] testCaseDidFinishForTestClass:event[@"className"] method:event[@"methodName"] withStatus:FBTestReportStatusFailed duration:duration logs:nil];

  NSData *data = [NSJSONSerialization dataWithJSONObject:event options:0 error:NULL];
  [self.adapter handleEventJSONData:data];
  [mock verify];
}

- (void)test_LogicReporter_testCaseDidFail_fromError
{
  OCMockObject *mock = self.reporterMock;
  NSMutableDictionary *event = [testEventDict() mutableCopy];
  NSTimeInterval duration = 0.0050642;
  event[@"totalDuration"] = @(duration);
  event[@"event"] = @"end-test";
  event[@"result"] = @"error";

  NSString *message = @"The message to win all messages";
  NSUInteger line = 969;
  NSString *file = @"dasLiebstenFeile";
  event[@"exceptions"] = @[@{
    @"reason": message,
    @"lineNumber": @(line),
    @"filePathInProject": file,
  }];
  [[mock expect] testCaseDidFailForTestClass:event[@"className"] method:event[@"methodName"] withMessage:message file:file line:line];
  [[mock expect] testCaseDidFinishForTestClass:event[@"className"] method:event[@"methodName"] withStatus:FBTestReportStatusFailed duration:duration logs:nil];

  NSData *data = [NSJSONSerialization dataWithJSONObject:event options:0 error:NULL];
  [self.adapter handleEventJSONData:data];
  [mock verify];
}

- (void)test_LogicReporter_testCaseDidSucceed
{
  OCMockObject *mock = self.reporterMock;
  NSMutableDictionary *event = [testEventDict() mutableCopy];
  event[@"event"] = @"begin-event";
  NSTimeInterval duration = 0.0050642;
  event[@"totalDuration"] = @(duration);
  event[@"event"] = @"end-test";
  event[@"result"] = @"success";

  [[mock expect] testCaseDidFinishForTestClass:event[@"className"] method:event[@"methodName"] withStatus:FBTestReportStatusPassed duration:duration logs:nil];

  NSData *data = [NSJSONSerialization dataWithJSONObject:event options:0 error:NULL];
  [self.adapter handleEventJSONData:data];
  [mock verify];
}

- (void)test_LogicReporter_testSuiteDidEnd
{
  OCMockObject *mock = self.reporterMock;
  NSDictionary *dict = @{
    @"event": @"end-test-suite",
    @"suite": @"Toplevel Test Suite",
    @"testCaseCount": @10,
    @"testDuration": @"0.148857057094574",
    @"timestamp": @"1510917478.156559",
    @"totalDuration": @"0.1503260135650635",
    @"totalFailureCount": @4,
    @"unexpectedExceptionCount": @0,
  };

  FBTestManagerResultSummary *expectedSummary = summaryFromDictionary(dict);
  [[mock expect] finishedWithSummary:expectedSummary];
  NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:NULL];
  [self.adapter handleEventJSONData:data];
  [mock verify];
}

@end
