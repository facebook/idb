/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestReporterAdapter.h"

#import "FBXCTestReporter.h"

@interface FBXCTestReporterAdapter ()

@property (nonatomic, strong) id<FBXCTestReporter> reporter;

@end

@implementation FBXCTestReporterAdapter

+ (instancetype)adapterWithReporter:(id<FBXCTestReporter>)reporter
{
  FBXCTestReporterAdapter *adapter = [self new];
  adapter->_reporter = reporter;
  return adapter;
}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testBundleReadyWithProtocolVersion:(NSInteger)protocolVersion minimumVersion:(NSInteger)minimumVersion
{
}

- (void)testManagerMediatorDidBeginExecutingTestPlan:(FBTestManagerAPIMediator *)mediator
{
  [_reporter didBeginExecutingTestPlan];
}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testSuite:(NSString *)testSuite didStartAt:(NSString *)startTime
{
  [_reporter testSuite:testSuite didStartAt:startTime];
}
- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testPlanDidFailWithMessage:(NSString *)message
{
  if ([_reporter respondsToSelector:@selector(testPlanDidFailWithMessage:)]) {
    [_reporter testPlanDidFailWithMessage:message];
  }
}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testCaseDidStartForTestClass:(NSString *)testClass method:(NSString *)method
{
  [_reporter testCaseDidStartForTestClass:testClass method:method];
}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testCaseDidFailForTestClass:(NSString *)testClass method:(NSString *)method withMessage:(NSString *)message file:(NSString *)file line:(NSUInteger)line
{
  [_reporter testCaseDidFailForTestClass:testClass method:method withMessage:message file:file line:line];
}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(FBTestReportStatus)status duration:(NSTimeInterval)duration
{
  [self testManagerMediator:mediator testCaseDidFinishForTestClass:testClass method:method withStatus:status duration:duration logs: nil];
}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(FBTestReportStatus)status duration:(NSTimeInterval)duration logs:(NSArray<NSString *> *)logs
{
  [_reporter testCaseDidFinishForTestClass:testClass method:method withStatus:status duration:duration logs:logs];
}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator finishedWithSummary:(FBTestManagerResultSummary *)summary
{
  [_reporter finishedWithSummary:summary];
}

- (void)testManagerMediatorDidFinishExecutingTestPlan:(FBTestManagerAPIMediator *)mediator
{
  [_reporter didFinishExecutingTestPlan];
}

- (void)appUnderTestExited {
  if ([_reporter respondsToSelector:@selector(appUnderTestExited)]) {
    [_reporter appUnderTestExited];
  }
}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testCase:(NSString *)testClass method:(NSString *)method willStartActivity:(FBActivityRecord *)activity
{
  if ([_reporter respondsToSelector:@selector(testCase:method:willStartActivity:)]) {
    [_reporter testCase:testClass method:method willStartActivity:activity];
  }
}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testCase:(NSString *)testClass method:(NSString *)method didFinishActivity:(FBActivityRecord *)activity
{
  if ([_reporter respondsToSelector:@selector(testCase:method:didFinishActivity:)]) {
    [_reporter testCase:testClass method:method didFinishActivity:activity];
  }
}

@end
