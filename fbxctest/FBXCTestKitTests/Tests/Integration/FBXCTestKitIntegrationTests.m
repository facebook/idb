/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestKitFixtures.h"

#import <FBXCTestKit/FBXCTestKit.h>
#import <XCTest/XCTest.h>

#import "FBXCTestReporterDouble.h"
#import "XCTestCase+FBXCTestKitTests.h"

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

+ (NSDictionary<NSString *, NSString *> *)stallingProcessUnderTestEnvironment
{
  return @{
    @"TEST_FIXTURE_SHOULD_STALL" : @"1",
  };
}

- (FBXCTestContext *)context
{
  return [FBXCTestContext contextWithReporter:self.reporter logger:self.logger];
}

- (BOOL)validateShimsForTestExecution
{
  NSError *error = nil;
  if ([[FBXCTestShimConfiguration findShimDirectoryOnQueue:dispatch_get_main_queue()] await:&error]) {
    return YES;
  }
  NSLog(@"Could not locate a shim directory, skipping %@", error);
  return NO;
}

- (void)testiOSUITestRun
{
  NSError *error;
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *applicationPath = [FBXCTestKitFixtures testRunnerApp];
  NSString *testTargetPath = [FBXCTestKitFixtures iOSUITestAppTargetPath];
  NSString *testBundlePath = self.iOSUITestBundlePath;
  NSString *appTestArgument = [NSString stringWithFormat:@"%@:%@:%@", testBundlePath, applicationPath, testTargetPath];
  NSArray *arguments = @[ @"run-tests", @"-destination", @"name=iPhone 8", @"-uiTest", appTestArgument ];

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:@{} workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);

  FBXCTestBaseRunner *testRunner = [FBXCTestBaseRunner testRunnerWithCommandLine:commandLine context:self.context];
  BOOL success = [[testRunner execute] await:&error] != nil;
  XCTAssertTrue(success);
  XCTAssertNil(error);

  XCTAssertTrue(self.reporter.printReportWasCalled);

  NSArray<NSArray<NSString *> *> *uiTestList = @[
    @[@"iOSUITestFixtureUITests", @"testHelloWorld"],
  ];
  XCTAssertEqualObjects(self.reporter.startedTests, uiTestList);
  XCTAssertEqualObjects(self.reporter.passedTests, uiTestList);
  XCTAssertEqualObjects(self.reporter.failedTests, @[]);
}

- (void)testRunsiOSUnitTestInApplication
{
  NSError *error;
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *applicationPath = [FBXCTestKitFixtures tableSearchApplicationPath];
  NSString *testBundlePath = [self iOSUnitTestBundlePath];
  NSString *appTestArgument = [NSString stringWithFormat:@"%@:%@", testBundlePath, applicationPath];
  NSArray *arguments = @[ @"run-tests", @"-destination", @"name=iPhone 8", @"-appTest", appTestArgument ];

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:@{} workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);

  FBXCTestBaseRunner *testRunner = [FBXCTestBaseRunner testRunnerWithCommandLine:commandLine context:self.context];
  BOOL success = [[testRunner execute] await:&error] != nil;
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
    @[@"iOSUnitTestFixtureTests", @"testPossibleStallingOfHostProcess"],
    @[@"iOSUnitTestFixtureTests", @"testWillAlwaysFail"],
    @[@"iOSUnitTestFixtureTests", @"testWillAlwaysPass"],
  ];
  XCTAssertEqualObjects(expected, self.reporter.startedTests);
  expected = @[
    @[@"iOSUnitTestFixtureTests", @"testIsRunningInIOSApp"],
    @[@"iOSUnitTestFixtureTests", @"testIsRunningOnIOS"],
    @[@"iOSUnitTestFixtureTests", @"testPossibleCrashingOfHostProcess"],
    @[@"iOSUnitTestFixtureTests", @"testPossibleStallingOfHostProcess"],
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
  if (XCTestCase.isRunningOnTravis) {
    return;
  }

  NSError *error;
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *applicationPath = [FBXCTestKitFixtures tableSearchApplicationPath];
  NSString *testBundlePath = [self iOSUnitTestBundlePath];
  NSString *appTestArgument = [NSString stringWithFormat:@"%@:%@", testBundlePath, applicationPath];
  NSArray *arguments = @[ @"run-tests", @"-destination", @"name=iPhone 8", @"-appTest", appTestArgument ];
  NSDictionary<NSString *, NSString *> *processUnderTestEnvironment = FBXCTestKitIntegrationTests.crashingProcessUnderTestEnvironment;

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:processUnderTestEnvironment workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);

  FBXCTestBaseRunner *testRunner = [FBXCTestBaseRunner testRunnerWithCommandLine:commandLine context:self.context];
  BOOL success = [[testRunner execute] await:&error] != nil;
  XCTAssertFalse(success);
  XCTAssertNotNil(error);

  XCTAssertFalse(self.reporter.printReportWasCalled);
  XCTAssertTrue([error.description containsString:@"testPossibleCrashingOfHostProcess"]);
}

- (void)testRunAppTestWithFilter
{
  NSError *error;
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *applicationPath = [FBXCTestKitFixtures iOSUITestAppTargetPath];
  NSString *testBundlePath = [self iOSAppTestBundlePath];
  NSString *appTestArgument = [NSString stringWithFormat:@"%@:%@", testBundlePath, applicationPath];
  NSString *shortTestFilter = @"iOSAppFixtureAppTests/testWillAlwaysPass";
  NSString *testFilter = [NSString stringWithFormat:@"%@:%@", testBundlePath, shortTestFilter];
  NSArray *arguments = @[ @"run-tests", @"-destination", @"name=iPhone 8", @"-appTest", appTestArgument, @"-only", testFilter];

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine  commandLineFromArguments:arguments processUnderTestEnvironment:@{} workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);

  FBXCTestBaseRunner *testRunner = [FBXCTestBaseRunner testRunnerWithCommandLine:commandLine context:self.context];
  BOOL success = [[testRunner execute] await:&error] != nil;
  XCTAssertTrue(success);
  XCTAssertNil(error);

  XCTAssertTrue(self.reporter.printReportWasCalled);
  NSArray<NSArray<NSString *> *> *expected = @[@[@"iOSAppFixtureAppTests", @"testWillAlwaysPass"]];
  XCTAssertEqualObjects(expected, self.reporter.startedTests);
}

- (void)testRunAppTestWithTailingOSLog
{
  NSError *error;
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *applicationPath = [FBXCTestKitFixtures iOSUITestAppTargetPath];
  NSString *testBundlePath = [self iOSAppTestBundlePath];
  NSString *appTestArgument = [NSString stringWithFormat:@"%@:%@", testBundlePath, applicationPath];
  NSArray *arguments = @[ @"run-tests", @"-destination", @"name=iPhone 8", @"-appTest", appTestArgument];
  NSString *osLogPath = [workingDirectory stringByAppendingPathComponent:@"os_log.txt"];

  XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:osLogPath isDirectory:nil], @"should have no os log file");

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine  commandLineFromArguments:arguments processUnderTestEnvironment:@{@"FBXCTEST_OS_LOG_PATH": osLogPath} workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);

  FBXCTestBaseRunner *testRunner = [FBXCTestBaseRunner testRunnerWithCommandLine:commandLine context:self.context];
  BOOL success = [[testRunner execute] await:&error] != nil;
  XCTAssertTrue(success);
  XCTAssertNil(error);

  XCTAssertTrue(self.reporter.printReportWasCalled);
  NSArray<NSArray<NSString *> *> *expected = @[
                                               @[@"iOSAppFixtureAppTests", @"testWillAlwaysFail"],
                                               @[@"iOSAppFixtureAppTests", @"testWillAlwaysPass"],
                                               ];
  XCTAssertEqualObjects(expected, self.reporter.startedTests);
  XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:osLogPath isDirectory:nil], @"should create os log file");
}

- (void)testRunsiOSLogicTestsWithoutApplication
{
  NSError *error = nil;
  if (![self validateShimsForTestExecution]) {
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [self iOSUnitTestBundlePath];
  NSArray *arguments = @[ @"run-tests", @"-destination", @"name=iPhone 8", @"-logicTest", testBundlePath ];

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine  commandLineFromArguments:arguments processUnderTestEnvironment:@{} workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);

  FBXCTestBaseRunner *testRunner = [FBXCTestBaseRunner testRunnerWithCommandLine:commandLine context:self.context];
  BOOL success = [[testRunner execute] await:&error] != nil;
  XCTAssertTrue(success);
  XCTAssertNil(error);

  XCTAssertTrue(self.reporter.printReportWasCalled);
  XCTAssertEqual(self.reporter.startedSuites.count, 2u);
  XCTAssertEqual(self.reporter.startedTests.count, 10u);
  XCTAssertEqual(self.reporter.passedTests.count, 5u);
  XCTAssertEqual(self.reporter.failedTests.count, 5u);
}

- (void)testiOSLogicTestEndsOnCrashingTest
{
  NSError *error = nil;
  if (![self validateShimsForTestExecution]) {
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [self iOSUnitTestBundlePath];
  NSArray *arguments = @[ @"run-tests", @"-destination", @"name=iPhone 8", @"-logicTest", testBundlePath ];
  NSDictionary<NSString *, NSString *> *processUnderTestEnvironment = FBXCTestKitIntegrationTests.crashingProcessUnderTestEnvironment;

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:processUnderTestEnvironment workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);

  FBXCTestBaseRunner *testRunner = [FBXCTestBaseRunner testRunnerWithCommandLine:commandLine context:self.context];
  BOOL success = [[testRunner execute] await:&error] != nil;
  XCTAssertFalse(success);
  XCTAssertNotNil(error);
  XCTAssertTrue([error.description containsString:@"testPossibleCrashingOfHostProcess"]);

  XCTAssertFalse(self.reporter.printReportWasCalled);
  XCTAssertEqual(self.reporter.startedSuites.count, 2u);
  XCTAssertEqual(self.reporter.startedTests.count, 7u);
  XCTAssertEqual(self.reporter.passedTests.count, 2u);
  XCTAssertEqual(self.reporter.failedTests.count, 4u);
}

- (void)testiOSLogicTestEndsOnStallingTest
{
  NSError *error = nil;
  if (![self validateShimsForTestExecution]) {
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [self iOSUnitTestBundlePath];
  NSArray *arguments = @[ @"run-tests", @"-destination", @"name=iPhone 8", @"-logicTest", testBundlePath ];
  NSDictionary<NSString *, NSString *> *processUnderTestEnvironment = FBXCTestKitIntegrationTests.stallingProcessUnderTestEnvironment;

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:processUnderTestEnvironment workingDirectory:workingDirectory timeout:5 error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);

  FBXCTestBaseRunner *testRunner = [FBXCTestBaseRunner testRunnerWithCommandLine:commandLine context:self.context];
  BOOL success = [[testRunner execute] await:&error] != nil;
  XCTAssertFalse(success);
  XCTAssertNotNil(error);
  XCTAssertTrue([error.description containsString:@"testPossibleStallingOfHostProcess"]);

  XCTAssertFalse(self.reporter.printReportWasCalled);
  XCTAssertEqual(self.reporter.startedSuites.count, 2u);
  XCTAssertEqual(self.reporter.startedTests.count, 8u);
  XCTAssertEqual(self.reporter.passedTests.count, 3u);
  XCTAssertEqual(self.reporter.failedTests.count, 4u);
}

- (void)testiOSTestList
{
  NSError *error = nil;
  if (![self validateShimsForTestExecution]) {
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [self iOSUnitTestBundlePath];
  NSArray *arguments = @[ @"run-tests", @"-destination", @"name=iPhone 8", @"-logicTest", testBundlePath, @"-listTestsOnly" ];

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:@{} workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);

  FBXCTestBaseRunner *testRunner = [FBXCTestBaseRunner testRunnerWithCommandLine:commandLine context:self.context];
  BOOL success = [[testRunner execute] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  XCTAssertTrue(self.reporter.printReportWasCalled);
  NSArray<NSArray<NSString *> *> *expected = @[
    @[@"iOSUnitTestFixtureTests", @"testHostProcessIsMobileSafari"],
    @[@"iOSUnitTestFixtureTests", @"testHostProcessIsXctest"],
    @[@"iOSUnitTestFixtureTests", @"testIsRunningInIOSApp"],
    @[@"iOSUnitTestFixtureTests", @"testIsRunningInMacOSXApp"],
    @[@"iOSUnitTestFixtureTests", @"testIsRunningOnIOS"],
    @[@"iOSUnitTestFixtureTests", @"testIsRunningOnMacOSX"],
    @[@"iOSUnitTestFixtureTests", @"testPossibleCrashingOfHostProcess"],
    @[@"iOSUnitTestFixtureTests", @"testPossibleStallingOfHostProcess"],
    @[@"iOSUnitTestFixtureTests", @"testWillAlwaysFail"],
    @[@"iOSUnitTestFixtureTests", @"testWillAlwaysPass"],
  ];
  XCTAssertEqualObjects(expected, self.reporter.startedTests);
}

- (void)testiOSAppTestList
{
  NSError *error = nil;
  if (![self validateShimsForTestExecution]) {
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *applicationPath = [FBXCTestKitFixtures iOSUITestAppTargetPath];
  NSString *testBundlePath = [self iOSAppTestBundlePath];
  NSString *appTestArgument = [NSString stringWithFormat:@"%@:%@", testBundlePath, applicationPath];
  NSArray<NSString *> *arguments = @[ @"run-tests", @"-destination", @"name=iPhone 8", @"-appTest", appTestArgument, @"-listTestsOnly" ];

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:@{} workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);

  FBXCTestBaseRunner *testRunner = [FBXCTestBaseRunner testRunnerWithCommandLine:commandLine context:self.context];
  BOOL success = [[testRunner execute] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  XCTAssertTrue(self.reporter.printReportWasCalled);
  NSArray<NSArray<NSString *> *> *expected = @[
                                               @[@"iOSAppFixtureAppTests", @"testWillAlwaysFail"],
                                               @[@"iOSAppFixtureAppTests", @"testWillAlwaysPass"],
                                               ];
  XCTAssertEqualObjects(expected, self.reporter.startedTests);
}

- (void)testMacOSXLogicTest
{
  NSError *error = nil;
  if (![self validateShimsForTestExecution]) {
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [FBXCTestKitFixtures macUnitTestBundlePath];
  NSArray *arguments = @[ @"run-tests", @"-sdk", @"macosx", @"-logicTest", testBundlePath];

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:@{} workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);

  FBXCTestBaseRunner *testRunner = [FBXCTestBaseRunner testRunnerWithCommandLine:commandLine context:self.context];
  BOOL success = [[testRunner execute] await:&error] != nil;
  XCTAssertTrue(success);
  XCTAssertNil(error);

  XCTAssertTrue(self.reporter.printReportWasCalled);
  XCTAssertEqual(self.reporter.startedSuites.count, 2u);
  XCTAssertEqual(self.reporter.startedTests.count, 10u);
  XCTAssertEqual(self.reporter.passedTests.count, 6u);
  XCTAssertEqual(self.reporter.failedTests.count, 4u);
}

- (void)testMacOSXLogicTestEndsOnCrashingTest
{
  NSError *error = nil;
  if (![self validateShimsForTestExecution]) {
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [FBXCTestKitFixtures macUnitTestBundlePath];
  NSArray *arguments = @[ @"run-tests", @"-sdk", @"macosx", @"-logicTest", testBundlePath];
  NSDictionary<NSString *, NSString *> *processUnderTestEnvironment = FBXCTestKitIntegrationTests.crashingProcessUnderTestEnvironment;

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:processUnderTestEnvironment workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);

  FBXCTestBaseRunner *testRunner = [FBXCTestBaseRunner testRunnerWithCommandLine:commandLine context:self.context];
  BOOL success = [[testRunner execute] await:&error] != nil;
  XCTAssertFalse(success);
  XCTAssertNotNil(error);
  XCTAssertTrue([error.description containsString:@"testPossibleCrashingOfHostProcess"]);

  XCTAssertFalse(self.reporter.printReportWasCalled);
  XCTAssertEqual(self.reporter.startedSuites.count, 2u);
  XCTAssertEqual(self.reporter.startedTests.count, 7u);
  XCTAssertEqual(self.reporter.passedTests.count, 3u);
  XCTAssertEqual(self.reporter.failedTests.count, 3u);
}

- (void)testMacOSXApplicationTest
{
  NSError *error;
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *applicationPath = [FBXCTestKitFixtures macCommonAppPath];
  NSString *testBundlePath = [FBXCTestKitFixtures macUnitTestBundlePath];

  NSString *appTestArgument = [NSString stringWithFormat:@"%@:%@", testBundlePath, applicationPath];
  NSArray *arguments = @[ @"run-tests", @"-sdk", @"macosx", @"-appTest", appTestArgument ];

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:@{} workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);

  FBXCTestBaseRunner *testRunner = [FBXCTestBaseRunner testRunnerWithCommandLine:commandLine context:self.context];
  BOOL success = [[testRunner execute] await:&error] != nil;
  XCTAssertTrue(success);
  XCTAssertNil(error);

  XCTAssertTrue(self.reporter.printReportWasCalled);
  XCTAssertEqual(self.reporter.startedSuites.count, 3u);
  XCTAssertEqual(self.reporter.startedTests.count, 10u);
  XCTAssertEqual(self.reporter.passedTests.count, 6u);
  XCTAssertEqual(self.reporter.failedTests.count, 4u);
}

- (void)testMacOSXUITest
{
  NSError *error;
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *applicationPath = [FBXCTestKitFixtures macCommonAppPath];
  NSString *testBundlePath = [FBXCTestKitFixtures macUITestBundlePath];
  NSString *testTargetPath = [FBXCTestKitFixtures macUITestAppTargetPath];
  NSString *appTestArgument = [NSString stringWithFormat:@"%@:%@:%@", testBundlePath, applicationPath, testTargetPath];
  NSArray *arguments = @[ @"run-tests", @"-sdk", @"macosx", @"-uiTest", appTestArgument ];

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:@{} workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);

  FBXCTestBaseRunner *testRunner = [FBXCTestBaseRunner testRunnerWithCommandLine:commandLine context:self.context];
  BOOL success = [[testRunner execute] await:&error] != nil;
  XCTAssertTrue(success);
  XCTAssertNil(error);

  XCTAssertTrue(self.reporter.printReportWasCalled);

  NSArray<NSArray<NSString *> *> *uiTestList = @[
    @[@"MacUITestFixtureUITests", @"testHelloWorld"],
  ];
  XCTAssertEqualObjects(self.reporter.startedTests, uiTestList);
  XCTAssertEqualObjects(self.reporter.passedTests, uiTestList);
  XCTAssertEqualObjects(self.reporter.failedTests, @[]);
}

- (void)testMacOSXLogicTestEndsOnStallingTest
{
  NSError *error = nil;
  if (![self validateShimsForTestExecution]) {
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [FBXCTestKitFixtures macUnitTestBundlePath];
  NSArray *arguments = @[ @"run-tests", @"-sdk", @"macosx", @"-logicTest", testBundlePath];
  NSDictionary<NSString *, NSString *> *processUnderTestEnvironment = FBXCTestKitIntegrationTests.stallingProcessUnderTestEnvironment;

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:processUnderTestEnvironment workingDirectory:workingDirectory timeout:5 error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);

  FBXCTestBaseRunner *testRunner = [FBXCTestBaseRunner testRunnerWithCommandLine:commandLine context:self.context];
  BOOL success = [[testRunner execute] await:&error] != nil;
  XCTAssertFalse(success);
  XCTAssertNotNil(error);
  XCTAssertTrue([error.description containsString:@"testPossibleStallingOfHostProcess"]);

  XCTAssertFalse(self.reporter.printReportWasCalled);
  XCTAssertEqual(self.reporter.startedSuites.count, 2u);
  XCTAssertEqual(self.reporter.startedTests.count, 8u);
  XCTAssertEqual(self.reporter.passedTests.count, 4u);
  XCTAssertEqual(self.reporter.failedTests.count, 3u);
}

- (void)testReportsMacOSXTestList
{
  NSError *error = nil;
  if (![self validateShimsForTestExecution]) {
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [FBXCTestKitFixtures macUnitTestBundlePath];
  NSArray *arguments = @[ @"run-tests", @"-sdk", @"macosx", @"-logicTest", testBundlePath, @"-listTestsOnly" ];

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:@{} workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);

  FBXCTestBaseRunner *testRunner = [FBXCTestBaseRunner testRunnerWithCommandLine:commandLine context:self.context];
  BOOL success = [[testRunner execute] await:&error] != nil;
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
    @[@"MacUnitTestFixtureTests", @"testPossibleStallingOfHostProcess"],
    @[@"MacUnitTestFixtureTests", @"testWillAlwaysFail"],
    @[@"MacUnitTestFixtureTests", @"testWillAlwaysPass"],
  ];
  XCTAssertEqualObjects(expected, self.reporter.startedTests);
}

@end
