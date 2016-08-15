// Copyright 2004-present Facebook. All Rights Reserved.

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
  [_reporter testCaseDidFinishForTestClass:testClass method:method withStatus:status duration:duration];
}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator finishedWithSummary:(FBTestManagerResultSummary *)summary
{
  [_reporter finishedWithSummary:summary];
}

- (void)testManagerMediatorDidFinishExecutingTestPlan:(FBTestManagerAPIMediator *)mediator
{
  [_reporter didFinishExecutingTestPlan];
}

@end
