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

@interface FBiOSUITestConfigurationTests : FBControlCoreValueTestCase

@end

@implementation FBiOSUITestConfigurationTests

- (NSString *)appTestArgument
{
  NSString *testBundlePath = self.iOSUITestBundlePath;
  NSString *testHostAppPath = FBXCTestKitFixtures.tableSearchApplicationPath;
  NSString *applicationPath = FBXCTestKitFixtures.iOSUITestAppTargetPath;
  return [NSString stringWithFormat:@"%@:%@:%@", testBundlePath, testHostAppPath, applicationPath];
}

- (void)testiOSApplicationTestWithDestinationAndSDK
{
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSDictionary<NSString *, NSString *> *processEnvironment = @{@"FOO" : @"BAR"};
  NSArray<NSString *> *arguments = @[ @"run-tests", @"-sdk", @"iphonesimulator", @"-destination", @"name=iPhone 6", @"-uiTest", self.appTestArgument ];

  NSError *error = nil;
  FBXCTestConfiguration *configuration = [FBXCTestConfiguration configurationFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];

  XCTAssertNil(error);
  XCTAssertNotNil(configuration);
  XCTAssertTrue([configuration isKindOfClass:FBUITestConfiguration.class]);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([configuration.destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class]);
  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestConfiguration *expected = [FBUITestConfiguration
    configurationWithDestination:[[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:FBDeviceModeliPhone6 version:nil]
    environment:processEnvironment
    workingDirectory:workingDirectory
    testBundlePath:self.iOSUITestBundlePath
    waitForDebugger:NO
    timeout:0
    runnerAppPath:FBXCTestKitFixtures.tableSearchApplicationPath
    testTargetAppPath:FBXCTestKitFixtures.iOSUITestAppTargetPath];
  XCTAssertEqualObjects(configuration, expected);
}

- (void)testiOSApplicationTestWithDestinationWithoutSDK
{
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSDictionary<NSString *, NSString *> *processEnvironment = @{@"FOO" : @"BAR"};
  NSArray<NSString *> *arguments = @[ @"run-tests", @"-destination", @"name=iPhone 6", @"-uiTest", self.appTestArgument ];

  NSError *error = nil;
  FBXCTestConfiguration *configuration = [FBXCTestConfiguration configurationFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];

  XCTAssertNil(error);
  XCTAssertNotNil(configuration);
  XCTAssertTrue([configuration isKindOfClass:FBUITestConfiguration.class]);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([configuration.destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class]);
  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestConfiguration *expected = [FBUITestConfiguration
    configurationWithDestination:[[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:FBDeviceModeliPhone6 version:nil]
    environment:processEnvironment
    workingDirectory:workingDirectory
    testBundlePath:self.iOSUITestBundlePath
    waitForDebugger:NO
    timeout:0
    runnerAppPath:FBXCTestKitFixtures.tableSearchApplicationPath
    testTargetAppPath:FBXCTestKitFixtures.iOSUITestAppTargetPath];
  XCTAssertEqualObjects(configuration, expected);
}

- (void)testiOSApplicationTestsWithSDKWithoutDestination
{
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSDictionary<NSString *, NSString *> *processEnvironment = @{@"FOO" : @"BAR"};
  NSArray<NSString *> *arguments = @[ @"run-tests", @"-sdk", @"iphonesimulator", @"-uiTest", self.appTestArgument ];

  NSError *error = nil;
  FBXCTestConfiguration *configuration = [FBXCTestConfiguration configurationFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];

  XCTAssertNil(error);
  XCTAssertNotNil(configuration);
  XCTAssertTrue([configuration isKindOfClass:FBUITestConfiguration.class]);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([configuration.destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class]);
  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestConfiguration *expected = [FBUITestConfiguration
    configurationWithDestination:[[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:nil version:nil]
    environment:processEnvironment
    workingDirectory:workingDirectory
    testBundlePath:self.iOSUITestBundlePath
    waitForDebugger:NO
    timeout:0
    runnerAppPath:FBXCTestKitFixtures.tableSearchApplicationPath
    testTargetAppPath:FBXCTestKitFixtures.iOSUITestAppTargetPath];
  XCTAssertEqualObjects(configuration, expected);
}

- (void)testiOSApplicationTestsWithoutRunTestsAtStart
{
  NSError *error = nil;
  if (![FBXCTestShimConfiguration findShimDirectoryWithError:&error]) {
    NSLog(@"Could not locate a shim directory, skipping -[%@ %@]. %@", NSStringFromClass(self.class), NSStringFromSelector(_cmd), error);
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSDictionary<NSString *, NSString *> *processEnvironment = @{@"FOO" : @"BAR"};
  NSArray *arguments = @[ @"-reporter", @"json-stream", @"-sdk", @"iphonesimulator", @"run-tests", @"-uiTest", self.appTestArgument];

  FBXCTestConfiguration *configuration = [FBXCTestConfiguration configurationFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];

  XCTAssertNil(error);
  XCTAssertNotNil(configuration);
  XCTAssertFalse([configuration isKindOfClass:FBListTestConfiguration.class]);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([configuration.destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class]);
  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestConfiguration *expected = [FBUITestConfiguration
    configurationWithDestination:[[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:nil version:nil]
    environment:processEnvironment
    workingDirectory:workingDirectory
    testBundlePath:self.iOSUITestBundlePath
    waitForDebugger:NO
    timeout:0
    runnerAppPath:FBXCTestKitFixtures.tableSearchApplicationPath
    testTargetAppPath:FBXCTestKitFixtures.iOSUITestAppTargetPath];
  XCTAssertEqualObjects(configuration, expected);
}

@end
