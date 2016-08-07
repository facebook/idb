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

#define testSuiteDidStart(name, startTime)                                                                             \
  [self.reporter testManagerMediator:self.testManagerAPIMediator testSuite:name didStartAt:startTime]

#define testCaseDidFinish(className, methodName, status, time)                                                         \
  [self.reporter testManagerMediator:self.testManagerAPIMediator                                                       \
       testCaseDidFinishForTestClass:className                                                                         \
                              method:methodName                                                                        \
                          withStatus:status                                                                            \
                            duration:time]

#define testCaseDidStart(className, methodName)                                                                        \
  [self.reporter testManagerMediator:self.testManagerAPIMediator                                                       \
        testCaseDidStartForTestClass:className                                                                         \
                              method:methodName]

#define testCaseDidFail(className, methodName, message, inFile, atLine)                                                \
  [self.reporter testManagerMediator:self.testManagerAPIMediator                                                       \
         testCaseDidFailForTestClass:(NSString *)className                                                             \
                              method:(NSString *)methodName                                                            \
                         withMessage:(NSString *)message                                                               \
                                file:(NSString *)inFile                                                                \
                                line:(NSUInteger)atLine]

#define testSuiteDidFinish(name, finishTime, runCountValue, failureCount, unexpectedCount, testTime, totalTime)        \
  [self.reporter testManagerMediator:self.testManagerAPIMediator                                                       \
                 finishedWithSummary:[FBTestManagerResultSummary fromTestSuite:name                                    \
                                                                   finishingAt:finishTime                              \
                                                                      runCount:@(runCountValue)                        \
                                                                      failures:@(failureCount)                         \
                                                                    unexpected:@(unexpectedCount)                      \
                                                                  testDuration:@(testTime)                             \
                                                                 totalDuration:@(totalTime)]]

#define assertJUnitReportEqualTo(file, extension)                                                                      \
  [self.reporter testManagerMediatorDidFinishExecutingTestPlan:self.testManagerAPIMediator];                           \
  NSError *error;                                                                                                      \
  NSString *path =                                                                                                     \
      [[NSBundle bundleForClass:self.class] pathForResource:@"expectedJUnitReporterResult" ofType:@"xml"];             \
  NSString *expected = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];            \
  XCTAssertNil(error);                                                                                                 \
  NSString *actual =                                                                                                   \
      [[NSString alloc] initWithContentsOfFile:self.outputFilePath encoding:NSUTF8StringEncoding error:&error];        \
  XCTAssertNil(error);                                                                                                 \
  XCTAssertEqualObjects(expected, actual);

@interface FBTestManagerTestReporterJUnitTests : XCTestCase

@property (nonatomic) id testManagerAPIMediator;
@property (nonatomic) FBTestManagerTestReporterJUnit *reporter;
@property (nonatomic) NSFileHandle *outputFileHandle;
@property (nonatomic) NSString *outputFilePath;
@property (nonatomic, readonly) NSString *outputFileContent;

@end

@implementation FBTestManagerTestReporterJUnitTests

- (void)setUp
{
  [super setUp];

  self.testManagerAPIMediator = [OCMockObject mockForClass:[FBTestManagerAPIMediator class]];
  self.outputFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];

  [[NSFileManager defaultManager] createFileAtPath:self.outputFilePath contents:nil attributes:nil];

  self.outputFileHandle = [NSFileHandle fileHandleForWritingAtPath:self.outputFilePath];
  self.reporter = [FBTestManagerTestReporterJUnit withOutputFileHandle:self.outputFileHandle];
}

#pragma mark -

- (void)testJUnitReporter
{
  testSuiteDidStart(@"All Tests", @"2016-08-07 10:31:33");

  testSuiteDidStart(@"UnitTests.xctest", @"2016-08-07 10:31:34");
  testCaseDidStart(@"CalculatorTest", @"testMultiplication");
  testCaseDidFinish(@"CalculatorTest", @"testMultiplication", FBTestReportStatusPassed, 0.06);
  testCaseDidStart(@"CalculatorTest", @"testDivision");
  testCaseDidFail(@"CalculatorTest", @"testDivision", @"division by zero", @"CalculatorTest.m", 42);
  testCaseDidFinish(@"CalculatorTest", @"testDivision", FBTestReportStatusFailed, 0.12);
  testSuiteDidFinish(@"UnitTests.xctest", @"2016-08-07 10:31:35", 2, 1, 1, 0.18, 0.18);

  testSuiteDidStart(@"UITests.xctest", @"2016-08-07 10:31:36");
  testCaseDidStart(@"CalculatorInterfaceTest", @"testInteraction");
  testCaseDidFinish(@"CalculatorInterfaceTest", @"testInteraction", FBTestReportStatusPassed, 0.05);
  testSuiteDidFinish(@"UITests.xctest", @"2016-08-07 10:31:37", 1, 0, 0, 0.05, 0.05);

  testSuiteDidFinish(@"All Tests", @"2016-08-07 10:31:38", 3, 1, 1, 0.05, 0.23);

  assertJUnitReportEqualTo(@"expectedJUnitReporterResult", @"xml");
}

@end
