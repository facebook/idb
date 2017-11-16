/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>
#import <XCTestBootstrap/FBLogicReporterAdapter.h>
#import <XCTestBootstrap/FBXCTestReporter.h>
#import <OCMock/OCMock.h>

@interface FBLogicReporterAdapterTests : XCTestCase

@property (nonatomic, strong) FBLogicReporterAdapter *adapter;
@property (nonatomic, strong) OCMockObject *reporterMock;
@end

static NSDictionary *beginTestSuiteDict() {
  return @{
           @"event": @"begin-test-suite",
           @"suite": @"NARANJA",
           @"timestamp": @"1970"
         };
}

static NSDictionary *testEventDict() {
  return @{
           @"className": @"OmniClass",
           @"methodName": @"theMethod:toRule:themAll:"
         };
}

@implementation FBLogicReporterAdapterTests

- (void)setUp
{
  [super setUp];
  self.reporterMock = [OCMockObject mockForProtocol:@protocol(FBXCTestReporter)];
  self.adapter = [[FBLogicReporterAdapter alloc] initWithReporter:(id)self.reporterMock];
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

- (void)test_LogicReporter_testCaseDidFail
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
                             @"filePathInProject": file
                            }];
  [[mock expect] testCaseDidFailForTestClass:event[@"className"] method:event[@"methodName"] withMessage:message file:file line:line];
  [[mock expect] testCaseDidFinishForTestClass:event[@"className"] method:event[@"methodName"] withStatus:FBTestReportStatusFailed duration:duration];

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

  [[mock expect] testCaseDidFinishForTestClass:event[@"className"] method:event[@"methodName"] withStatus:FBTestReportStatusPassed duration:duration];

  NSData *data = [NSJSONSerialization dataWithJSONObject:event options:0 error:NULL];
  [self.adapter handleEventJSONData:data];
  [mock verify];
}

@end
