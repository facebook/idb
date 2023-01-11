/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestReporterAdapter.h"

#import <XCTestPrivate/XCTestManager_IDEInterface-Protocol.h>
#import <XCTestPrivate/XCActivityRecord.h>

#import "FBActivityRecord.h"
#import "FBTestManagerAPIMediator.h"
#import "FBTestManagerResultSummary.h"
#import "FBXCTestReporter.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@interface FBTestReporterAdapter ()

@property (nonatomic, strong, readonly) id<FBXCTestReporter> reporter;

@end

@implementation FBTestReporterAdapter

+ (instancetype)withReporter:(id<FBXCTestReporter>)reporter;
{
  return [[self alloc] initWithReporter:reporter];
}

- (instancetype)initWithReporter:(id<FBXCTestReporter>)reporter;
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _reporter = reporter;

  return self;
}


#pragma mark Protocol Implementation

- (id)_XCT_testSuite:(NSString *)tests didStartAt:(NSString *)time
{
  [self.reporter testSuite:tests didStartAt:time];
  return nil;
}

- (id)_XCT_didBeginExecutingTestPlan
{
  [self.reporter didBeginExecutingTestPlan];
  return nil;
}

- (id)_XCT_testCaseDidStartForTestClass:(NSString *)testClass method:(NSString *)method
{
  [self.reporter testCaseDidStartForTestClass:testClass method:method];
  return nil;
}

- (id)_XCT_testCaseDidFailForTestClass:(NSString *)testClass method:(NSString *)method withMessage:(NSString *)message file:(NSString *)file line:(NSNumber *)line
{
    [self.reporter testCaseDidFailForTestClass:testClass method:method exceptions:@[
        [[FBExceptionInfo alloc]initWithMessage:message file:file line:line.unsignedIntegerValue
        ]]];
  return nil;
}

- (id)_XCT_didFinishExecutingTestPlan
{
  [self.reporter didFinishExecutingTestPlan];
  return nil;
}

- (id)_XCT_testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(NSString *)statusString duration:(NSNumber *)duration
{
  FBTestReportStatus status = [FBTestManagerResultSummary statusForStatusString:statusString];
  [self.reporter testCaseDidFinishForTestClass:testClass method:method withStatus:status duration:duration.doubleValue logs:@[]];
  return nil;
}

- (id)_XCT_testSuite:(NSString *)testSuite didFinishAt:(NSString *)time runCount:(NSNumber *)runCount withFailures:(NSNumber *)failures unexpected:(NSNumber *)unexpected testDuration:(NSNumber *)testDuration totalDuration:(NSNumber *)totalDuration
{
  FBTestManagerResultSummary *summary = [FBTestManagerResultSummary fromTestSuite:testSuite finishingAt:time runCount:runCount failures:failures unexpected:unexpected testDuration:testDuration totalDuration:totalDuration];
  [self.reporter finishedWithSummary:summary];
  return nil;
}

- (id)_XCT_testCase:(NSString *)testClass method:(NSString *)method didFinishActivity:(XCActivityRecord *)activity
{
  FBActivityRecord *wrapped = [FBActivityRecord from:activity];
  if ([self.reporter respondsToSelector:@selector(testCase:method:didFinishActivity:)]) {
    [self.reporter testCase:testClass method:method didFinishActivity:wrapped];
  }
  return nil;
}

- (id)_XCT_testCase:(NSString *)testClass method:(NSString *)method willStartActivity:(XCActivityRecord *)activity
{
  FBActivityRecord *wrapped = [FBActivityRecord from:activity];
  if ([self.reporter respondsToSelector:@selector(testCase:method:willStartActivity:)]) {
    [self.reporter testCase:testClass method:method willStartActivity:wrapped];
  }
  return nil;
}

@end

#pragma clang diagnostic pop
