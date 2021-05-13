/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "CoreSimulatorDoubles.h"
#import "FBSimulatorControlTestCase.h"
#import "FBSimulatorControlFixtures.h"
#import "FBSimulatorControlAssertions.h"

@interface FBSimulatorTestInjection : FBSimulatorControlTestCase <FBXCTestReporter>

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

- (nullable FBSimulator *)assertObtainsBootedSimulatorWithTableSearch
{
  FBSimulator *simulator = [self assertObtainsBootedSimulator];
  if (!simulator) {
    return nil;
  }
  NSError *error = nil;
  BOOL success = [[simulator installApplicationWithPath:self.tableSearchApplication.path] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  return simulator;
}

- (void)assertLaunchesTestWithConfiguration:(FBTestLaunchConfiguration *)testLaunch reporter:(id<FBXCTestReporter>)reporter simulator:(FBSimulator *)simulator
{
  NSError *error = nil;
  id result = [[simulator runTestWithLaunchConfiguration:testLaunch reporter:reporter logger:simulator.logger] await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(result);
}

- (void)testInjectsApplicationTestIntoSampleApp
{
  FBSimulator *simulator = [self assertObtainsBootedSimulatorWithTableSearch];
  [self assertLaunchesTestWithConfiguration:self.testLaunchTableSearch reporter:self simulator:simulator];
  [self assertPassed:@[@"testIsRunningOnIOS", @"testIsRunningInIOSApp", @"testPossibleCrashingOfHostProcess", @"testPossibleStallingOfHostProcess", @"testWillAlwaysPass"]
              failed:@[@"testHostProcessIsMobileSafari", @"testHostProcessIsXctest", @"testIsRunningInMacOSXApp", @"testIsRunningOnMacOSX", @"testWillAlwaysFail"]];
}

- (void)testInjectsApplicationTestIntoSafari
{
  FBSimulator *simulator = [self assertObtainsBootedSimulator];
  [self assertLaunchesTestWithConfiguration:self.testLaunchSafari reporter:self simulator:simulator];
  [self assertPassed:@[@"testIsRunningOnIOS", @"testIsRunningInIOSApp", @"testHostProcessIsMobileSafari", @"testPossibleCrashingOfHostProcess", @"testPossibleStallingOfHostProcess", @"testWillAlwaysPass"]
              failed:@[@"testHostProcessIsXctest", @"testIsRunningInMacOSXApp", @"testIsRunningOnMacOSX", @"testWillAlwaysFail"]];
}

- (void)testInjectsApplicationTestWithCustomOutputConfiguration
{
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
  XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil]);

  NSString *stdErrPath = [path stringByAppendingPathComponent:@"stderr.log"];
  NSString *stdOutPath = [path stringByAppendingPathComponent:@"stdout.log"];
  FBProcessOutputConfiguration *output = [FBProcessOutputConfiguration configurationWithStdOut:stdOutPath stdErr:stdErrPath error:nil];
  FBApplicationLaunchConfiguration *applicationLaunchConfiguration = [self.safariAppLaunch withOutput:output];
  FBTestLaunchConfiguration *testLaunch = [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testLaunchSafari.testBundlePath
    applicationLaunchConfiguration:applicationLaunchConfiguration
    testHostPath:nil
    timeout:0
    initializeUITesting:NO
    useXcodebuild:NO
    testsToRun:nil
    testsToSkip:nil
    targetApplicationPath:nil
    targetApplicationBundleID:nil
    xcTestRunProperties:nil
    resultBundlePath:nil
    reportActivities:NO
    coveragePath:nil
    shims:nil];

  FBSimulator *simulator = [self assertObtainsBootedSimulator];
  [self assertLaunchesTestWithConfiguration:testLaunch reporter:self simulator:simulator];

  NSFileManager *fileManager = [NSFileManager defaultManager];
  XCTAssertTrue([fileManager fileExistsAtPath:stdErrPath]);
  XCTAssertTrue([fileManager fileExistsAtPath:stdOutPath]);

  NSString *stdErrContent = [[NSString alloc] initWithContentsOfFile:stdErrPath encoding:NSUTF8StringEncoding error:nil];
  XCTAssertTrue([stdErrContent containsString:@"Started running iOSUnitTestFixtureTests"]);
}

- (void)assertPassed:(NSArray<NSString *> *)passed failed:(NSArray<NSString *> *)failed
{
  XCTAssertEqualObjects(self.passedMethods, [NSSet setWithArray:passed]);
  XCTAssertEqualObjects(self.failedMethods, [NSSet setWithArray:failed]);
}

- (void)testInjectsApplicationTestWithTestsToRun
{
  FBSimulator *simulator = [self assertObtainsBootedSimulator];
  FBTestLaunchConfiguration *testLaunch = [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testLaunchSafari.testBundlePath
    applicationLaunchConfiguration:self.safariAppLaunch
    testHostPath:nil
    timeout:0
    initializeUITesting:NO
    useXcodebuild:NO
    testsToRun:[NSSet setWithArray:@[@"iOSUnitTestFixtureTests/testIsRunningOnIOS", @"iOSUnitTestFixtureTests/testWillAlwaysFail"]]
    testsToSkip:nil
    targetApplicationPath:nil
    targetApplicationBundleID:nil
    xcTestRunProperties:nil
    resultBundlePath:nil
    reportActivities:NO
    coveragePath:nil
    shims:nil];

  [self assertLaunchesTestWithConfiguration:testLaunch reporter:self simulator:simulator];
  [self assertPassed:@[@"testIsRunningOnIOS"]
              failed:@[@"testWillAlwaysFail"]];
}

- (void)testInjectsApplicationTestWithTestsToSkip
{
  FBSimulator *simulator = [self assertObtainsBootedSimulator];
  FBTestLaunchConfiguration *testLaunch = [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testLaunchSafari.testBundlePath
    applicationLaunchConfiguration:self.safariAppLaunch
    testHostPath:nil
    timeout:0
    initializeUITesting:NO
    useXcodebuild:NO
    testsToRun:nil
    testsToSkip:[NSSet setWithArray:@[@"iOSUnitTestFixtureTests/testIsRunningOnIOS", @"iOSUnitTestFixtureTests/testWillAlwaysFail"]]
    targetApplicationPath:nil
    targetApplicationBundleID:nil
    xcTestRunProperties:nil
    resultBundlePath:nil
    reportActivities:NO
    coveragePath:nil
    shims:nil];

  [self assertLaunchesTestWithConfiguration:testLaunch reporter:self simulator:simulator];
  [self assertPassed:@[@"testIsRunningInIOSApp", @"testHostProcessIsMobileSafari", @"testPossibleCrashingOfHostProcess", @"testPossibleStallingOfHostProcess", @"testWillAlwaysPass"]
              failed:@[@"testHostProcessIsXctest", @"testIsRunningInMacOSXApp", @"testIsRunningOnMacOSX"]];
}

#pragma mark FBXCTestReporter

- (void)didBeginExecutingTestPlan
{

}

- (void)testSuite:(NSString *)testSuite didStartAt:(NSString *)startTime
{

}

- (void)testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(FBTestReportStatus)status duration:(NSTimeInterval)duration
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

- (void)testCaseDidFailForTestClass:(NSString *)testClass method:(NSString *)method withMessage:(NSString *)message file:(NSString *)file line:(NSUInteger)line
{

}

- (void)testBundleReadyWithProtocolVersion:(NSInteger)protocolVersion minimumVersion:(NSInteger)minimumVersion
{

}

- (void)testCaseDidStartForTestClass:(NSString *)testClass method:(NSString *)method
{
}

- (void)finishedWithSummary:(FBTestManagerResultSummary *)summary
{
  XCTAssertNotNil(summary.finishTime);
  XCTAssertNotNil(summary.testSuite);
}

- (void)didFinishExecutingTestPlan
{

}

- (void)appUnderTestExited
{

}

- (void)debuggerAttached
{

}

- (void)didCrashDuringTest:(NSError *)error
{

}


- (void)handleExternalEvent:(NSString *)event
{

}


- (BOOL)printReportWithError:(NSError **)error
{
  return YES;
}

- (void)processWaitingForDebuggerWithProcessIdentifier:(pid_t)pid
{

}

- (void)testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(FBTestReportStatus)status duration:(NSTimeInterval)duration logs:(NSArray<NSString *> *)logs
{

}

- (void)testHadOutput:(NSString *)output
{

}

@end
