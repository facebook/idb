/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestKitFixtures.h"

#import <FBXCTestKit/FBXCTestKit.h>
#import <XCTest/XCTest.h>

#import "FBXCTestReporterDouble.h"

@interface FBXCTestKitIntegrationTests : XCTestCase

@property (nonatomic, strong, readwrite) FBXCTestReporterDouble *reporter;

@end

@implementation FBXCTestKitIntegrationTests

- (void)setUp
{
  self.reporter = [FBXCTestReporterDouble new];
}

+ (NSDictionary<NSString *, NSString *> *)crashingProcessUnderTestEnvironment
{
  return @{
    @"TEST_FIXTURE_SHOULD_CRASH" : @"1",
  };
}

- (void)testRunsiOSUnitTestInApplication
{
  NSError *error;
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *applicationPath = [FBXCTestKitFixtures tableSearchApplicationPath];
  NSString *testBundlePath = [self iOSUnitTestBundlePath];
  NSString *appTestArgument = [NSString stringWithFormat:@"%@:%@", testBundlePath, applicationPath];
  NSArray *arguments = @[ @"run-tests", @"-destination", @"name=iPhone 6", @"-appTest", appTestArgument ];

  FBTestRunConfiguration *configuration = [[FBTestRunConfiguration alloc] initWithReporter:self.reporter processUnderTestEnvironment:@{}];
  BOOL success = [configuration loadWithArguments:arguments workingDirectory:workingDirectory error:&error];
  XCTAssertTrue(success);
  XCTAssertNil(error);

  FBXCTestRunner *testRunner = [FBXCTestRunner testRunnerWithConfiguration:configuration];
  success = [testRunner executeTestsWithError:&error];
  XCTAssertTrue(success);
  XCTAssertNil(error);

  XCTAssertTrue(self.reporter.printReportWasCalled);
  NSArray<NSArray<NSString *> *> *expected = @[
    @[@"iOSUnitTestFixtureTests", @"testHostProcessIsMobileSafari"],
    @[@"iOSUnitTestFixtureTests", @"testHostProcessIsXctest"],
    @[@"iOSUnitTestFixtureTests", @"testIsRunningInIOSApp"],
    @[@"iOSUnitTestFixtureTests", @"testIsRunningInMacOSXApp"],
    @[@"iOSUnitTestFixtureTests", @"testIsRunningOnIOS"],
    @[@"iOSUnitTestFixtureTests", @"testIsRunningOnMacOSX"],
    @[@"iOSUnitTestFixtureTests", @"testPossibleCrashingOfHostProcess"],
    @[@"iOSUnitTestFixtureTests", @"testWillAlwaysFail"],
    @[@"iOSUnitTestFixtureTests", @"testWillAlwaysPass"],
  ];
  XCTAssertEqualObjects(expected, self.reporter.startedTests);
  expected = @[
    @[@"iOSUnitTestFixtureTests", @"testIsRunningInIOSApp"],
    @[@"iOSUnitTestFixtureTests", @"testIsRunningOnIOS"],
    @[@"iOSUnitTestFixtureTests", @"testPossibleCrashingOfHostProcess"],
    @[@"iOSUnitTestFixtureTests", @"testWillAlwaysPass"],
  ];
  XCTAssertEqualObjects(expected, self.reporter.passedTests);
  expected = @[
    @[@"iOSUnitTestFixtureTests", @"testHostProcessIsMobileSafari"],
    @[@"iOSUnitTestFixtureTests", @"testHostProcessIsXctest"],
    @[@"iOSUnitTestFixtureTests", @"testIsRunningInMacOSXApp"],
    @[@"iOSUnitTestFixtureTests", @"testIsRunningOnMacOSX"],
    @[@"iOSUnitTestFixtureTests", @"testWillAlwaysFail"],
  ];
  XCTAssertEqualObjects(expected, self.reporter.failedTests);
}

- (void)testApplicationTestEndsOnCrashingTest
{
  NSError *error;
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *applicationPath = [FBXCTestKitFixtures tableSearchApplicationPath];
  NSString *testBundlePath = [self iOSUnitTestBundlePath];
  NSString *appTestArgument = [NSString stringWithFormat:@"%@:%@", testBundlePath, applicationPath];
  NSArray *arguments = @[ @"run-tests", @"-destination", @"name=iPhone 6", @"-appTest", appTestArgument ];
  NSDictionary<NSString *, NSString *> *processUnderTestEnvironment = FBXCTestKitIntegrationTests.crashingProcessUnderTestEnvironment;

  FBTestRunConfiguration *configuration = [[FBTestRunConfiguration alloc] initWithReporter:self.reporter processUnderTestEnvironment:processUnderTestEnvironment];
  BOOL success = [configuration loadWithArguments:arguments workingDirectory:workingDirectory error:&error];
  XCTAssertTrue(success);
  XCTAssertNil(error);

  FBXCTestRunner *testRunner = [FBXCTestRunner testRunnerWithConfiguration:configuration];
  success = [testRunner executeTestsWithError:&error];
  XCTAssertFalse(success);
  XCTAssertNotNil(error);
  XCTAssertFalse(self.reporter.printReportWasCalled);
}

- (void)testRunsiOSLogicTestsWithoutApplication
{
  NSError *error = nil;
  if (![FBTestRunConfiguration findShimDirectoryWithError:&error]) {
    NSLog(@"Could not locate a shim directory, skipping -[%@ %@]. %@", NSStringFromClass(self.class), NSStringFromSelector(_cmd), error);
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [self iOSUnitTestBundlePath];
  NSArray *arguments = @[ @"run-tests", @"-destination", @"name=iPhone 6", @"-logicTest", testBundlePath ];

  FBTestRunConfiguration *configuration = [[FBTestRunConfiguration alloc] initWithReporter:self.reporter processUnderTestEnvironment:@{}];
  BOOL success = [configuration loadWithArguments:arguments workingDirectory:workingDirectory error:&error];
  XCTAssertTrue(success);
  XCTAssertNil(error);

  FBXCTestRunner *testRunner = [FBXCTestRunner testRunnerWithConfiguration:configuration];
  success = [testRunner executeTestsWithError:&error];
  XCTAssertTrue(success);
  XCTAssertNil(error);

  XCTAssertTrue(self.reporter.printReportWasCalled);
  XCTAssertEqual([self.reporter eventsWithName:@"begin-test-suite"].count, 1u);
  XCTAssertEqual([self.reporter eventsWithName:@"end-test-suite"].count, 1u);
  XCTAssertEqual([self.reporter eventsWithName:@"begin-test"].count, 9u);
  XCTAssertEqual([self.reporter eventsWithName:@"end-test"].count, 9u);
}

- (void)testiOSLogicTestEndsOnCrashingTest
{
  NSError *error = nil;
  if (![FBTestRunConfiguration findShimDirectoryWithError:&error]) {
    NSLog(@"Could not locate a shim directory, skipping -[%@ %@]. %@", NSStringFromClass(self.class), NSStringFromSelector(_cmd), error);
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [self iOSUnitTestBundlePath];
  NSArray *arguments = @[ @"run-tests", @"-destination", @"name=iPhone 6", @"-logicTest", testBundlePath ];
  NSDictionary<NSString *, NSString *> *processUnderTestEnvironment = FBXCTestKitIntegrationTests.crashingProcessUnderTestEnvironment;

  FBTestRunConfiguration *configuration = [[FBTestRunConfiguration alloc] initWithReporter:self.reporter processUnderTestEnvironment:processUnderTestEnvironment];
  BOOL success = [configuration loadWithArguments:arguments workingDirectory:workingDirectory error:&error];
  XCTAssertTrue(success);
  XCTAssertNil(error);

  FBXCTestRunner *testRunner = [FBXCTestRunner testRunnerWithConfiguration:configuration];
  success = [testRunner executeTestsWithError:&error];
  XCTAssertFalse(success);
  XCTAssertNotNil(error);

  XCTAssertFalse(self.reporter.printReportWasCalled);
  XCTAssertEqual([self.reporter eventsWithName:@"begin-test-suite"].count, 1u);
  XCTAssertEqual([self.reporter eventsWithName:@"end-test-suite"].count, 0u);
  XCTAssertEqual([self.reporter eventsWithName:@"begin-test"].count, 7u);
  XCTAssertEqual([self.reporter eventsWithName:@"end-test"].count, 6u);
}

- (void)testMacOSXLogicTest
{
  NSError *error = nil;
  if (![FBTestRunConfiguration findShimDirectoryWithError:&error]) {
    NSLog(@"Could not locate a shim directory, skipping -[%@ %@]. %@", NSStringFromClass(self.class), NSStringFromSelector(_cmd), error);
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [FBXCTestKitFixtures macUnitTestBundlePath];
  NSArray *arguments = @[ @"run-tests", @"-sdk", @"macosx", @"-logicTest", testBundlePath];

  FBTestRunConfiguration *configuration = [[FBTestRunConfiguration alloc] initWithReporter:self.reporter processUnderTestEnvironment:@{}];
  BOOL success = [configuration loadWithArguments:arguments workingDirectory:workingDirectory error:&error];
  XCTAssertTrue(success);
  XCTAssertNil(error);

  FBXCTestRunner *testRunner = [FBXCTestRunner testRunnerWithConfiguration:configuration];
  success = [testRunner executeTestsWithError:&error];
  XCTAssertTrue(success);
  XCTAssertNil(error);

  XCTAssertTrue(self.reporter.printReportWasCalled);
  XCTAssertEqual([self.reporter eventsWithName:@"begin-test-suite"].count, 1u);
  XCTAssertEqual([self.reporter eventsWithName:@"end-test-suite"].count, 1u);
  XCTAssertEqual([self.reporter eventsWithName:@"begin-test"].count, 9u);
  XCTAssertEqual([self.reporter eventsWithName:@"end-test"].count, 9u);
}

- (void)testMacOSXLogicTestEndsOnCrashingTest
{
  NSError *error = nil;
  if (![FBTestRunConfiguration findShimDirectoryWithError:&error]) {
    NSLog(@"Could not locate a shim directory, skipping -[%@ %@]. %@", NSStringFromClass(self.class), NSStringFromSelector(_cmd), error);
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [FBXCTestKitFixtures macUnitTestBundlePath];
  NSArray *arguments = @[ @"run-tests", @"-sdk", @"macosx", @"-logicTest", testBundlePath];
  NSDictionary<NSString *, NSString *> *processUnderTestEnvironment = FBXCTestKitIntegrationTests.crashingProcessUnderTestEnvironment;

  FBTestRunConfiguration *configuration = [[FBTestRunConfiguration alloc] initWithReporter:self.reporter processUnderTestEnvironment:processUnderTestEnvironment];
  BOOL success = [configuration loadWithArguments:arguments workingDirectory:workingDirectory error:&error];
  XCTAssertTrue(success);
  XCTAssertNil(error);

  FBXCTestRunner *testRunner = [FBXCTestRunner testRunnerWithConfiguration:configuration];
  success = [testRunner executeTestsWithError:&error];
  XCTAssertFalse(success);
  XCTAssertNotNil(error);

  XCTAssertFalse(self.reporter.printReportWasCalled);
  XCTAssertEqual([self.reporter eventsWithName:@"begin-test-suite"].count, 1u);
  XCTAssertEqual([self.reporter eventsWithName:@"end-test-suite"].count, 0u);
  XCTAssertEqual([self.reporter eventsWithName:@"begin-test"].count, 7u);
  XCTAssertEqual([self.reporter eventsWithName:@"end-test"].count, 6u);
}

- (void)testReportsMacOSXTestList
{
  NSError *error = nil;
  if (![FBTestRunConfiguration findShimDirectoryWithError:&error]) {
    NSLog(@"Could not locate a shim directory, skipping -[%@ %@]. %@", NSStringFromClass(self.class), NSStringFromSelector(_cmd), error);
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [FBXCTestKitFixtures macUnitTestBundlePath];
  NSArray *arguments = @[ @"run-tests", @"-sdk", @"macosx", @"-logicTest", testBundlePath, @"-listTestsOnly" ];

  FBTestRunConfiguration *configuration = [[FBTestRunConfiguration alloc] initWithReporter:self.reporter processUnderTestEnvironment:@{}];
  BOOL success = [configuration loadWithArguments:arguments workingDirectory:workingDirectory error:&error];
  XCTAssertTrue(success);
  XCTAssertNil(error);

  FBXCTestRunner *testRunner = [FBXCTestRunner testRunnerWithConfiguration:configuration];
  success = [testRunner executeTestsWithError:&error];
  XCTAssertTrue(success);
  XCTAssertNil(error);

  XCTAssertTrue(self.reporter.printReportWasCalled);
  NSArray<NSArray<NSString *> *> *expected = @[
    @[@"MacUnitTestFixtureTests", @"testHostProcessIsMobileSafari"],
    @[@"MacUnitTestFixtureTests", @"testHostProcessIsXctest"],
    @[@"MacUnitTestFixtureTests", @"testIsRunningInIOSApp"],
    @[@"MacUnitTestFixtureTests", @"testIsRunningInMacOSXApp"],
    @[@"MacUnitTestFixtureTests", @"testIsRunningOnIOS"],
    @[@"MacUnitTestFixtureTests", @"testIsRunningOnMacOSX"],
    @[@"MacUnitTestFixtureTests", @"testPossibleCrashingOfHostProcess"],
    @[@"MacUnitTestFixtureTests", @"testWillAlwaysFail"],
    @[@"MacUnitTestFixtureTests", @"testWillAlwaysPass"],
  ];
  XCTAssertEqualObjects(expected, self.reporter.startedTests);
}

@end
