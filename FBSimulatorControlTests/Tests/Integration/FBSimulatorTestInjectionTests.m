/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "CoreSimulatorDoubles.h"
#import "FBSimulatorControlTestCase.h"
#import "FBSimulatorPoolTestCase.h"
#import "FBSimulatorControlFixtures.h"
#import "FBSimulatorControlAssertions.h"

@interface FBSimulatorTestInjection : FBSimulatorControlTestCase <FBTestManagerTestReporter>

@property (nonatomic, strong, readwrite) NSMutableSet *passedMethods;
@property (nonatomic, strong, readwrite) NSMutableSet *failedMethods;

@end

@implementation FBSimulatorTestInjection

#pragma mark Lifecycle

- (void)setUp
{
  [super setUp];
  self.passedMethods = [NSMutableSet set];
  self.failedMethods = [NSMutableSet set];
}

#pragma mark Tests

- (void)testInjectsApplicationTestIntoSampleApp
{
  FBSimulator *simulator = [self assertObtainsBootedSimulator];
  id<FBInteraction> interaction = [[[simulator.interact
    installApplication:self.tableSearchApplication]
    startTestWithLaunchConfiguration:self.testLaunch reporter:self]
    waitUntilAllTestRunnersHaveFinishedTestingWithTimeout:20];
  [self assertInteractionSuccessful:interaction];
  [self assertPassed:@[@"testIsRunningOnIOS", @"testIsRunningInIOSApp", @"testPossibleCrashingOfHostProcess", @"testPossibleStallingOfHostProcess", @"testWillAlwaysPass"]
              failed:@[@"testHostProcessIsMobileSafari", @"testHostProcessIsXctest", @"testIsRunningInMacOSXApp", @"testIsRunningOnMacOSX", @"testWillAlwaysFail"]];
}

- (void)testInjectsApplicationTestIntoSampleAppOnIOS81Simulator
{
  if (FBControlCoreGlobalConfiguration.isXcode8OrGreater) {
    NSLog(@"Skipping running -[%@ %@] since Xcode 7 or smaller is required", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
    return;
  }
  self.simulatorConfiguration = FBSimulatorConfiguration.iPhone5.iOS_8_1;
  FBSimulator *simulator = [self assertObtainsBootedSimulator];
  id<FBInteraction> interaction = [[[simulator.interact
    installApplication:self.tableSearchApplication]
    startTestWithLaunchConfiguration:self.testLaunch reporter:self]
    waitUntilAllTestRunnersHaveFinishedTestingWithTimeout:20];
  [self assertInteractionSuccessful:interaction];
  [self assertPassed:@[@"testIsRunningOnIOS", @"testIsRunningInIOSApp", @"testPossibleCrashingOfHostProcess", @"testPossibleStallingOfHostProcess", @"testWillAlwaysPass"]
              failed:@[@"testHostProcessIsMobileSafari", @"testHostProcessIsXctest", @"testIsRunningInMacOSXApp", @"testIsRunningOnMacOSX", @"testWillAlwaysFail"]];
}

- (void)testInjectsApplicationTestIntoSafari
{

  FBSimulator *simulator = [self assertObtainsBootedSimulator];
  id<FBInteraction> interaction = [[simulator.interact
    startTestWithLaunchConfiguration:[self.testLaunch withApplicationLaunchConfiguration:self.safariAppLaunch] reporter:self]
    waitUntilAllTestRunnersHaveFinishedTestingWithTimeout:20];

  [self assertInteractionSuccessful:interaction];
  [self assertPassed:@[@"testIsRunningOnIOS", @"testIsRunningInIOSApp", @"testHostProcessIsMobileSafari", @"testPossibleCrashingOfHostProcess", @"testPossibleStallingOfHostProcess", @"testWillAlwaysPass"]
              failed:@[@"testHostProcessIsXctest", @"testIsRunningInMacOSXApp", @"testIsRunningOnMacOSX", @"testWillAlwaysFail"]];
}

- (void)assertPassed:(NSArray<NSString *> *)passed failed:(NSArray<NSString *> *)failed
{
  XCTAssertEqualObjects(self.passedMethods, [NSSet setWithArray:passed]);
  XCTAssertEqualObjects(self.failedMethods, [NSSet setWithArray:failed]);
}

- (void)testInjectsApplicationTestIntoSampleAppWithJUnitReporter
{
  NSURL *outputFileURL =
      [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString]];
  FBTestManagerTestReporterJUnit *reporter = [FBTestManagerTestReporterJUnit withOutputFileURL:outputFileURL];
  FBSimulator *simulator = [self assertObtainsBootedSimulator];
  id<FBInteraction> interaction = [[[simulator.interact installApplication:self.tableSearchApplication]
      startTestWithLaunchConfiguration:self.testLaunch reporter:reporter]
      waitUntilAllTestRunnersHaveFinishedTestingWithTimeout:20];
  [self assertInteractionSuccessful:interaction];

  NSURL *fixtureFileURL = [NSURL fileURLWithPath:[FBSimulatorControlFixtures JUnitXMLResult0Path]];
  NSString *expected = [self stringWithContentsOfJUnitResult:fixtureFileURL];
  NSString *actual = [self stringWithContentsOfJUnitResult:outputFileURL];

  XCTAssertEqualObjects(expected, actual);
}

#pragma mark -

- (NSString *)stringWithContentsOfJUnitResult:(NSURL *)path
{
  NSError *error;
  NSString *string = [NSString stringWithContentsOfURL:path encoding:NSUTF8StringEncoding error:&error];
  XCTAssertNil(error);

  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"time=\"[^\"]+\""
                                                                         options:NSRegularExpressionCaseInsensitive
                                                                           error:&error];
  XCTAssertNil(error);

  return [regex stringByReplacingMatchesInString:string
                                         options:0
                                           range:NSMakeRange(0, string.length)
                                    withTemplate:@"time=\"0.00\""];
}

#pragma mark FBTestManagerTestReporter

- (void)testManagerMediatorDidBeginExecutingTestPlan:(FBTestManagerAPIMediator *)mediator
{

}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testSuite:(NSString *)testSuite didStartAt:(NSString *)startTime
{

}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(FBTestReportStatus)status duration:(NSTimeInterval)duration
{
  switch (status) {
    case FBTestReportStatusPassed:
      [self.passedMethods addObject:method];
      break;
    case FBTestReportStatusFailed:
      [self.failedMethods addObject:method];
    case FBTestReportStatusUnknown:
      break;
  }
}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testCaseDidFailForTestClass:(NSString *)testClass method:(NSString *)method withMessage:(NSString *)message file:(NSString *)file line:(NSUInteger)line
{

}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testBundleReadyWithProtocolVersion:(NSInteger)protocolVersion minimumVersion:(NSInteger)minimumVersion
{

}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testCaseDidStartForTestClass:(NSString *)testClass method:(NSString *)method
{
}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator finishedWithSummary:(FBTestManagerResultSummary *)summary
{
  XCTAssertNotNil(summary.finishTime);
  XCTAssertNotNil(summary.testSuite);
}

- (void)testManagerMediatorDidFinishExecutingTestPlan:(FBTestManagerAPIMediator *)mediator
{

}

@end
