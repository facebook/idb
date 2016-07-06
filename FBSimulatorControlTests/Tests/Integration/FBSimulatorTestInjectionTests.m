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
  FBSimulator *simulator = [self obtainBootedSimulator];
  id<FBInteraction> interaction = [[simulator.interact
    installApplication:self.tableSearchApplication]
    startTestRunnerLaunchConfiguration:self.tableSearchAppLaunch testBundlePath:self.applicationTestBundlePath reporter:self];

  [self assertInteractionSuccessful:interaction];
  [self assertPassed:@[@"testIsRunningOnIOS"] failed:@[@"testIsRunningOnMacOSX", @"testIsSafari"]];

}

- (void)testInjectsApplicationTestIntoSampleAppOnIOS81Simulator
{
  self.simulatorConfiguration = FBSimulatorConfiguration.iPhone5.iOS_8_1;
  FBSimulator *simulator = [self obtainBootedSimulator];
  id<FBInteraction> interaction = [[simulator.interact
    installApplication:self.tableSearchApplication]
    startTestRunnerLaunchConfiguration:self.tableSearchAppLaunch testBundlePath:self.applicationTestBundlePath reporter:self];

  [self assertInteractionSuccessful:interaction];
  [self assertPassed:@[@"testIsRunningOnIOS"] failed:@[@"testIsRunningOnMacOSX", @"testIsSafari"]];
}

- (void)testInjectsApplicationTestIntoSafari
{
  FBSimulator *simulator = [self obtainBootedSimulator];
  id<FBInteraction> interaction = [simulator.interact
    startTestRunnerLaunchConfiguration:self.safariAppLaunch testBundlePath:self.applicationTestBundlePath reporter:self];

  [self assertInteractionSuccessful:interaction];
  [self assertPassed:@[@"testIsRunningOnIOS", @"testIsSafari"] failed:@[@"testIsRunningOnMacOSX"]];
}

- (void)assertPassed:(NSArray<NSString *> *)passed failed:(NSArray<NSString *> *)failed
{
  BOOL success = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.regularTimeout untilTrue:^BOOL{
    return [self.passedMethods isEqualToSet:[NSSet setWithArray:passed]];
  }];
  XCTAssertTrue(success);
  success = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout untilTrue:^BOOL{
    return [self.failedMethods isEqualToSet:[NSSet setWithArray:failed]];
  }];
  XCTAssertTrue(success);
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

}

- (void)testManagerMediatorDidFinishExecutingTestPlan:(FBTestManagerAPIMediator *)mediator
{

}

@end
