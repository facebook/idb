/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>
#import <XCTestBootstrap/FBLogicReporterAdapter.h>
#import <XCTestBootstrap/FBXCTestReporter.h>
#import <XCTestBootstrap/FBTestManagerResultSummary.h>
#import "FBXCTestReporterDouble.h"

@interface FBLogicReporterAdapterTests : XCTestCase

@property (nonatomic, strong, nullable, readwrite) FBLogicReporterAdapter *adapter;
@property (nonatomic, strong, nullable, readwrite) FBXCTestReporterDouble *reporterDouble;

@end

static NSDictionary *beginTestSuiteDict(void) {
  return @{
    @"event": @"begin-test-suite",
    @"suite": @"NARANJA",
    @"timestamp": @"1970",
  };
}

static NSDictionary *testEventDict(void) {
  return @{
    @"className": @"OmniClass",
    @"methodName": @"theMethod:toRule:themAll:",
  };
}

@implementation FBLogicReporterAdapterTests

- (void)setUp
{
  [super setUp];
  self.reporterDouble = [[FBXCTestReporterDouble alloc] init];
  self.adapter = [[FBLogicReporterAdapter alloc] initWithReporter:self.reporterDouble logger:nil];
}

- (void)test_LogicReporter_testSuiteDidStart
{
  NSData *data = [NSJSONSerialization dataWithJSONObject:beginTestSuiteDict() options:0 error:NULL];


  [self.adapter handleEventJSONData:data];
  XCTAssertEqualObjects(self.reporterDouble.startedSuites, @[@"NARANJA"]);
}

- (void)test_LogicReporter_testCaseDidStart
{
  NSMutableDictionary *event = [testEventDict() mutableCopy];
  event[@"event"] = @"begin-test";

  NSData *data = [NSJSONSerialization dataWithJSONObject:event options:0 error:NULL];
  [self.adapter handleEventJSONData:data];

  XCTAssertEqualObjects(self.reporterDouble.startedTests, (@[@[event[@"className"], event[@"methodName"]]]));
}

- (void)test_LogicReporter_testCaseDidFail_fromFailure
{
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

  NSData *data = [NSJSONSerialization dataWithJSONObject:event options:0 error:NULL];
  [self.adapter handleEventJSONData:data];

  XCTAssertEqualObjects(self.reporterDouble.failedTests, (@[@[event[@"className"], event[@"methodName"]]]));
}

- (void)test_LogicReporter_testCaseDidFail_fromError
{
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

  NSData *data = [NSJSONSerialization dataWithJSONObject:event options:0 error:NULL];
  [self.adapter handleEventJSONData:data];

  XCTAssertEqualObjects(self.reporterDouble.failedTests, (@[@[event[@"className"], event[@"methodName"]]]));
}

- (void)test_LogicReporter_testCaseDidSucceed
{
  NSMutableDictionary *event = [testEventDict() mutableCopy];
  event[@"event"] = @"begin-event";
  NSTimeInterval duration = 0.0050642;
  event[@"totalDuration"] = @(duration);
  event[@"event"] = @"end-test";
  event[@"result"] = @"success";

  NSData *data = [NSJSONSerialization dataWithJSONObject:event options:0 error:NULL];
  [self.adapter handleEventJSONData:data];

  XCTAssertEqualObjects(self.reporterDouble.passedTests, (@[@[event[@"className"], event[@"methodName"]]]));
}

- (void)test_LogicReporter_testSuiteDidEnd
{
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

  NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:NULL];
  [self.adapter handleEventJSONData:data];

  XCTAssertEqualObjects(self.reporterDouble.endedSuites, (@[@"Toplevel Test Suite"]));
}

@end
