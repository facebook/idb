/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <OCMock/OCMock.h>
#import <XCTest/XCTest.h>

#import "FBTestManagerAPIMediator.h"
#import "FBTestManagerResultSummary.h"
#import "FBTestManagerTestReporterJUnit.h"

@interface FBTestManagerTestReporterJUnitTests : XCTestCase

@property (nonatomic) id testManagerAPIMediator;
@property (nonatomic) FBTestManagerTestReporterJUnit *reporter;
@property (nonatomic) NSURL *outputFileURL;
@property (nonatomic, readonly) NSString *outputFileContent;

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

  NSString *actual = [self reporterResult];
  NSString *expected = [self expectedReporterResult:@"FBTestManagerTestReporterJUnitTests_testJUnitReporter.xml"];

  XCTAssertEqualObjects(expected, actual);
}

#pragma mark -

- (NSString *)expectedReporterResult:(NSString *)filename
{
  NSArray *resource = [filename componentsSeparatedByString:@"."];
  NSString *path =
      [[NSBundle bundleForClass:self.class] pathForResource:resource.firstObject ofType:resource.lastObject];
  NSError *error;
  NSString *expectedReporterResult =
      [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
  XCTAssertNil(error);
  return expectedReporterResult;
}

- (NSString *)reporterResult
{
  [self.reporter testManagerMediatorDidFinishExecutingTestPlan:self.testManagerAPIMediator];
  NSError *error;
  NSString *reporterResult =
      [[NSString alloc] initWithContentsOfURL:self.outputFileURL encoding:NSUTF8StringEncoding error:&error];
  XCTAssertNil(error);
  return reporterResult;
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

@end
