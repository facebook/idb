/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestKitFixtures.h"

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBXCTestKit/FBXCTestKit.h>
#import <XCTest/XCTest.h>

#import "FBXCTestReporterDouble.h"
#import "XCTestCase+FBXCTestKitTests.h"
#import "FBControlCoreValueTestCase.h"

@interface FBiOSApplicationTestConfigurationTests : FBControlCoreValueTestCase

@end

@implementation FBiOSApplicationTestConfigurationTests

- (void)testiOSApplicationTestsWithTestFilter
{
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testAppPath = [FBXCTestKitFixtures iOSUITestAppTargetPath];
  NSString *testBundlePath = [FBXCTestKitFixtures iOSAppTestBundlePath];
  NSString *appTestArgument = [NSString stringWithFormat:@"%@:%@", testBundlePath, testAppPath];
  NSString *shortTestFilter = @"iOSAppFixtureAppTests/testWillAlwaysPass";
  NSString *testFilter = [NSString stringWithFormat:@"%@:%@", testBundlePath, shortTestFilter];

  NSDictionary<NSString *, NSString *> *processEnvironment = @{@"FOO" : @"BAR"};
  NSArray<NSString *> *arguments = @[@"run-tests",
                                     @"-sdk", @"iphonesimulator",
                                     @"-destination", @"name=iPhone 6",
                                     @"-appTest", appTestArgument,
                                     @"-only", testFilter];

  NSError *error;
  FBXCTestConfiguration *configuration = [FBXCTestConfiguration configurationFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];

  XCTAssertNil(error);
  XCTAssertNotNil(configuration);
  XCTAssertTrue([configuration isKindOfClass:FBTestManagerTestConfiguration.class]);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([configuration.destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class]);
  XCTAssertEqual(configuration.waitForDebugger, NO);
  XCTAssertEqual(configuration.testType, FBXCTestTypeApplicationTest);

  [self assertValueSemanticsOfConfiguration:configuration];

  FBTestManagerTestConfiguration *testManagerTestConfiguration = (FBTestManagerTestConfiguration *)configuration;
  XCTAssertEqualObjects(testManagerTestConfiguration.testFilter, shortTestFilter);
}

@end
