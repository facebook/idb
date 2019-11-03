/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <OCMock/OCMock.h>
#import <XCTest/XCTest.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBXCTestBootstrapFixtures.h"

@interface FBTestManagerTestReporterJUnitTests : XCTestCase

@property (nonatomic, strong) id testManagerAPIMediator;
@property (nonatomic, strong) FBTestManagerTestReporterJUnit *reporter;
@property (nonatomic, strong) NSURL *outputFileURL;
@property (nonatomic, copy, readonly) NSString *outputFileContent;

@end

@implementation FBTestManagerTestReporterJUnitTests

- (void)setUp
{
  [super setUp];

  self.testManagerAPIMediator = [OCMockObject mockForClass:[FBTestManagerAPIMediator class]];
  self.outputFileURL =
      [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString]];

  self.reporter = [FBTestManagerTestReporterJUnit withOutputFileURL:self.outputFileURL];
}

#pragma mark -

- (void)testJUnitReporter
{
  [self testSuite:@"All Tests" didStartAt:@"2016-08-07 10:31:33"];

  [self testSuite:@"UnitTests.xctest" didStartAt:@"2016-08-07 10:31:34"];
  [self testCaseDidStart:@"CalculatorTest" method:@"testMultiplication"];
  [self testCaseDidFinish:@"CalculatorTest" method:@"testMultiplication" status:FBTestReportStatusPassed duration:0.06];
  [self testCaseDidStart:@"CalculatorTest" method:@"testDivision"];
  [self testCaseDidFail:@"CalculatorTest" method:@"testDivision" withMessage:@"division by zero" file:@"CalculatorTest.m" line:42];
  [self testCaseDidFinish:@"CalculatorTest" method:@"testDivision" status:FBTestReportStatusFailed duration:0.12];
  [self testSuiteDidFinish:@"UnitTests.xctest" at:@"2016-08-07 10:31:35" runCount:2 failures:1 unexpected:1 testDuration:0.18 totalDuration:0.18];

  [self testSuite:@"UITests.xctest" didStartAt:@"2016-08-07 10:31:36"];
  [self testCaseDidStart:@"CalculatorInterfaceTest" method:@"testInteraction"];
  [self testCaseDidFinish:@"CalculatorInterfaceTest" method:@"testInteraction" status:FBTestReportStatusPassed duration:0.05];
  [self testSuiteDidFinish:@"UITests.xctest" at:@"2016-08-07 10:31:37" runCount:1 failures:0 unexpected:0 testDuration:0.05 totalDuration:0.05];

  [self testSuiteDidFinish:@"All Tests" at:@"2016-08-07 10:31:38" runCount:3 failures:1 unexpected:1 testDuration:0.05 totalDuration:0.23];

  [self testManagerMediatorDidFinishExecutingTestPlan];

  NSURL *fixtureFileURL = [NSURL fileURLWithPath:[FBTestManagerTestReporterJUnitTests JUnitXMLResult0Path]];
  NSString *actual = [self stringWithContentsOfJUnitResult:self.outputFileURL];
  NSString *expected = [self stringWithContentsOfJUnitResult:fixtureFileURL];

  XCTAssertEqualObjects(expected, actual);
}

- (void)testJUnitReporterWithManyNestedTestSuites
{
  [self testSuite:@"One" didStartAt:@"2016-08-07 10:31:33"];
  [self testCaseDidStart:@"TestOne" method:@"method"];
  [self testCaseDidFinish:@"TestOne" method:@"method" status:FBTestReportStatusPassed duration:0.05];
  [self testSuite:@"Two" didStartAt:@"2016-08-07 10:31:34"];
  [self testCaseDidStart:@"TestTwo" method:@"method"];
  [self testCaseDidFinish:@"TestTwo" method:@"method" status:FBTestReportStatusPassed duration:0.05];
  [self testSuite:@"Three" didStartAt:@"2016-08-07 10:31:35"];
  [self testCaseDidStart:@"TestThree" method:@"method"];
  [self testCaseDidFinish:@"TestThree" method:@"method" status:FBTestReportStatusPassed duration:0.05];
  [self testSuite:@"Four" didStartAt:@"2016-08-07 10:31:36"];
  [self testCaseDidStart:@"TestFour" method:@"method"];
  [self testCaseDidFinish:@"TestFour" method:@"method" status:FBTestReportStatusPassed duration:0.05];
  [self testSuiteDidFinish:@"Four" at:@"2016-08-07 10:31:37" runCount:1 failures:0 unexpected:0 testDuration:0.05 totalDuration:0.05];
  [self testSuiteDidFinish:@"Three" at:@"2016-08-07 10:31:38" runCount:2 failures:0 unexpected:0 testDuration:0.05 totalDuration:0.05];
  [self testSuiteDidFinish:@"Two" at:@"2016-08-07 10:31:39" runCount:3 failures:0 unexpected:0 testDuration:0.05 totalDuration:0.05];
  [self testSuiteDidFinish:@"One" at:@"2016-08-07 10:31:34" runCount:4 failures:0 unexpected:0 testDuration:0.05 totalDuration:0.05];

  [self testManagerMediatorDidFinishExecutingTestPlan];

  NSURL *fixtureFileURL = [NSURL fileURLWithPath:[FBTestManagerTestReporterJUnitTests JUnitXMLResult1Path]];
  NSString *actual = [self stringWithContentsOfJUnitResult:self.outputFileURL];
  NSString *expected = [self stringWithContentsOfJUnitResult:fixtureFileURL];

  XCTAssertEqualObjects(expected, actual);
}

#pragma mark -

- (NSString *)stringWithContentsOfJUnitResult:(NSURL *)path
{
  NSError *error;
  NSString *string = [NSString stringWithContentsOfURL:path encoding:NSUTF8StringEncoding error:&error];
  XCTAssertNil(error);
  return string;
}

- (void)testSuite:(NSString *)testSuite didStartAt:(NSString *)startTime
{
  [self.reporter testManagerMediator:self.testManagerAPIMediator testSuite:testSuite didStartAt:startTime];
}

- (void)testCaseDidStart:(NSString *)className method:(NSString *)methodName
{
  [self.reporter testManagerMediator:self.testManagerAPIMediator
        testCaseDidStartForTestClass:className
                              method:methodName];
}

- (void)testCaseDidFinish:(NSString *)className
                   method:(NSString *)methodName
                   status:(FBTestReportStatus)status
                 duration:(NSTimeInterval)duration
{
  [self.reporter testManagerMediator:self.testManagerAPIMediator
       testCaseDidFinishForTestClass:className
                              method:methodName
                          withStatus:status
                            duration:duration];
}

- (void)testCaseDidFail:(NSString *)className
                 method:(NSString *)methodName
            withMessage:(NSString *)message
                   file:(NSString *)inFile
                   line:(NSUInteger)atLine
{
  [self.reporter testManagerMediator:self.testManagerAPIMediator
         testCaseDidFailForTestClass:className
                              method:methodName
                         withMessage:message
                                file:inFile
                                line:atLine];
}

- (void)testSuiteDidFinish:(NSString *)testSuite
                        at:(NSString *)finishTime
                  runCount:(NSUInteger)runCount
                  failures:(NSUInteger)failures
                unexpected:(NSUInteger)unexpected
              testDuration:(NSTimeInterval)testDuration
             totalDuration:(NSTimeInterval)totalDuration
{
  FBTestManagerResultSummary *summary = [FBTestManagerResultSummary fromTestSuite:testSuite
                                                                      finishingAt:finishTime
                                                                         runCount:@(runCount)
                                                                         failures:@(failures)
                                                                       unexpected:@(unexpected)
                                                                     testDuration:@(testDuration)
                                                                    totalDuration:@(totalDuration)];
  [self.reporter testManagerMediator:self.testManagerAPIMediator finishedWithSummary:summary];
}

- (void)testManagerMediatorDidFinishExecutingTestPlan
{
  [self.reporter testManagerMediatorDidFinishExecutingTestPlan:self.testManagerAPIMediator];
}

@end
