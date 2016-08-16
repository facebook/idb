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

- (void)testRunTestsWithAppTest
{
  NSError *error;
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *applicationPath = [FBXCTestKitFixtures tableSearchApplicationPath];
  NSString *testBundlePath = [FBXCTestKitFixtures iOSUnitTestBundlePath];
  NSString *appTestArgument = [NSString stringWithFormat:@"%@:%@", testBundlePath, applicationPath];
  NSArray *arguments = @[ @"run-tests", @"-destination", @"name=iPhone 5,OS=iOS 9.3", @"-appTest", appTestArgument ];

  FBTestRunConfiguration *configuration = [[FBTestRunConfiguration alloc] initWithReporter:self.reporter];
  [configuration loadWithArguments:arguments workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);

  FBXCTestRunner *testRunner = [FBXCTestRunner testRunnerWithConfiguration:configuration];
  [testRunner executeTestsWithError:&error];
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

@end
