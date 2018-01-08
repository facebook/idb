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

@interface FBiOSLogicTestConfigurationTests : FBControlCoreValueTestCase

@end

@implementation FBiOSLogicTestConfigurationTests

- (void)testiOSLogicTestsWithDestinationAndSDK
{
  NSError *error = nil;
  if (![FBXCTestShimConfiguration findShimDirectoryWithError:&error]) {
    NSLog(@"Could not locate a shim directory, skipping -[%@ %@]. %@", NSStringFromClass(self.class), NSStringFromSelector(_cmd), error);
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [self iOSUnitTestBundlePath];
  NSDictionary<NSString *, NSString *> *processEnvironment = @{@"FOO" : @"BAR"};
  NSArray<NSString *> *arguments = @[ @"run-tests", @"-sdk", @"iphonesimulator", @"-destination", @"name=iPhone 6", @"-logicTest", testBundlePath ];

  FBXCTestConfiguration *configuration = [FBXCTestConfiguration configurationFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];

  XCTAssertNil(error);
  XCTAssertNotNil(configuration);
  XCTAssertNotNil(configuration.shims);
  XCTAssertTrue([configuration isKindOfClass:FBLogicTestConfiguration.class]);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([configuration.destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class]);
  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestConfiguration *expected = [FBLogicTestConfiguration
    configurationWithDestination:[[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:FBDeviceModeliPhone6 version:nil]
    shims:configuration.shims
    environment:processEnvironment
    workingDirectory:workingDirectory
    testBundlePath:self.iOSUnitTestBundlePath
    waitForDebugger:NO
    timeout:0
    testFilter:nil
    mirroring:FBLogicTestMirrorFileLogs];
  XCTAssertEqualObjects(configuration, expected);
}

- (void)testiOSLogicTestsWithDestinationWithoutSDK
{
  NSError *error = nil;
  if (![FBXCTestShimConfiguration findShimDirectoryWithError:&error]) {
    NSLog(@"Could not locate a shim directory, skipping -[%@ %@]. %@", NSStringFromClass(self.class), NSStringFromSelector(_cmd), error);
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [self iOSUnitTestBundlePath];
  NSDictionary<NSString *, NSString *> *processEnvironment = @{@"FOO" : @"BAR"};
  NSArray<NSString *> *arguments = @[ @"run-tests", @"-destination", @"name=iPhone 6", @"-logicTest", testBundlePath ];

  FBXCTestConfiguration *configuration = [FBXCTestConfiguration configurationFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];

  XCTAssertNil(error);
  XCTAssertNotNil(configuration);
  XCTAssertNotNil(configuration.shims);
  XCTAssertTrue([configuration isKindOfClass:FBLogicTestConfiguration.class]);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([configuration.destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class]);
  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestConfiguration *expected = [FBLogicTestConfiguration
    configurationWithDestination:[[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:FBDeviceModeliPhone6 version:nil]
    shims:configuration.shims
    environment:processEnvironment
    workingDirectory:workingDirectory
    testBundlePath:self.iOSUnitTestBundlePath
    waitForDebugger:NO
    timeout:0
    testFilter:nil
    mirroring:FBLogicTestMirrorFileLogs];
  XCTAssertEqualObjects(configuration, expected);

}

- (void)testiOSLogicTestsWithSDKWithoutDestination
{
  NSError *error = nil;
  if (![FBXCTestShimConfiguration findShimDirectoryWithError:&error]) {
    NSLog(@"Could not locate a shim directory, skipping -[%@ %@]. %@", NSStringFromClass(self.class), NSStringFromSelector(_cmd), error);
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [self iOSUnitTestBundlePath];
  NSDictionary<NSString *, NSString *> *processEnvironment = @{@"FOO" : @"BAR"};
  NSArray<NSString *> *arguments = @[ @"run-tests", @"-sdk", @"iphonesimulator", @"-logicTest", testBundlePath ];

  FBXCTestConfiguration *configuration = [FBXCTestConfiguration configurationFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];

  XCTAssertNil(error);
  XCTAssertNotNil(configuration);
  XCTAssertNotNil(configuration.shims);
  XCTAssertTrue([configuration isKindOfClass:FBLogicTestConfiguration.class]);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([configuration.destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class]);
  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestConfiguration *expected = [FBLogicTestConfiguration
    configurationWithDestination:[[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:nil version:nil]
    shims:configuration.shims
    environment:processEnvironment
    workingDirectory:workingDirectory
    testBundlePath:self.iOSUnitTestBundlePath
    waitForDebugger:NO
    timeout:0
    testFilter:nil
    mirroring:FBLogicTestMirrorFileLogs];
  XCTAssertEqualObjects(configuration, expected);
}

@end
