/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestManagerTestReporterBase.h"
#import "FBTestManagerResultSummary.h"
#import "FBTestManagerTestReporterTestCase.h"
#import "FBTestManagerTestReporterTestCaseFailure.h"
#import "FBTestManagerTestReporterTestSuite.h"

@interface FBTestManagerTestReporterBase ()

@property (nonatomic, strong) FBTestManagerTestReporterTestCase *currentTestCase;
@property (nonatomic, strong) FBTestManagerTestReporterTestSuite *currentTestSuite;
@property (nonatomic, strong) FBTestManagerTestReporterTestSuite *testSuite;

@end

@implementation FBTestManagerTestReporterBase

#pragma mark - FBTestManagerTestReporter

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator
    testBundleReadyWithProtocolVersion:(NSInteger)protocolVersion
                        minimumVersion:(NSInteger)minimumVersion
{
}

- (void)testManagerMediatorDidBeginExecutingTestPlan:(FBTestManagerAPIMediator *)mediator
{
}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator
                  testSuite:(NSString *)testSuite
                 didStartAt:(NSString *)startTime
{
  FBTestManagerTestReporterTestSuite *currentTestSuite =
      [FBTestManagerTestReporterTestSuite withName:testSuite startTime:startTime];

  // Add nested test suite
  if (self.currentTestSuite) {
    [self.currentTestSuite addTestSuite:currentTestSuite];
  }
  else {
    self.currentTestSuite = currentTestSuite;
    self.testSuite = currentTestSuite;
  }

  self.currentTestSuite = currentTestSuite;
}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator
    testCaseDidStartForTestClass:(NSString *)testClass
                          method:(NSString *)method
{
  FBTestManagerTestReporterTestCase *testCase =
      [FBTestManagerTestReporterTestCase withTestClass:testClass method:method];
  self.currentTestCase = testCase;
  [self.currentTestSuite addTestCase:testCase];
}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator
    testCaseDidFinishForTestClass:(NSString *)testClass
                           method:(NSString *)method
                       withStatus:(FBTestReportStatus)status
                         duration:(NSTimeInterval)duration
{
  NSAssert([self.currentTestCase.testClass isEqualToString:testClass] &&
               [self.currentTestCase.method isEqualToString:method],
           @"Unexpected testClass/method");

  [self.currentTestCase finishWithStatus:status duration:duration];
  self.currentTestCase = nil;
}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator
    testCaseDidFailForTestClass:(NSString *)testClass
                         method:(NSString *)method
                    withMessage:(NSString *)message
                           file:(NSString *)file
                           line:(NSUInteger)line
{
  [self.currentTestCase addFailure:[FBTestManagerTestReporterTestCaseFailure withMessage:message file:file line:line]];
}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator
        finishedWithSummary:(FBTestManagerResultSummary *)summary
{
  NSAssert([self.currentTestSuite.name isEqualToString:summary.testSuite], @"Unexpected testSuite");

  [self.currentTestSuite finishWithSummary:summary];
  if (self.currentTestSuite.parent) {
    self.currentTestSuite = self.currentTestSuite.parent;
  }
}

- (void)testManagerMediatorDidFinishExecutingTestPlan:(FBTestManagerAPIMediator *)mediator
{
}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testCase:(NSString *)testClass method:(NSString *)method willStartActivity:(FBActivityRecord *)activity
{
}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testCase:(NSString *)testClass method:(NSString *)method didFinishActivity:(FBActivityRecord *)activity
{
}

@end
