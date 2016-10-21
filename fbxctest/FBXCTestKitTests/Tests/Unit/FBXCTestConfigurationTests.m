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

@interface FBXCTestConfigurationTests : XCTestCase

@property (nonatomic, strong, readwrite) FBXCTestReporterDouble *reporter;

@end

@implementation FBXCTestConfigurationTests

- (void)setUp
{
  self.reporter = [FBXCTestReporterDouble new];
}

- (void)testiOSApplicationTests
{
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *applicationPath = [FBXCTestKitFixtures tableSearchApplicationPath];
  NSString *testBundlePath = [self iOSUnitTestBundlePath];
  NSString *appTestArgument = [NSString stringWithFormat:@"%@:%@", testBundlePath, applicationPath];
  NSDictionary<NSString *, NSString *> *processEnvironment = @{@"FOO" : @"BAR"};
  NSArray<NSString *> *arguments = @[ @"run-tests", @"-destination", @"name=iPhone 6", @"-appTest", appTestArgument ];

  FBXCTestConfiguration *configuration = [[FBXCTestConfiguration alloc] initWithReporter:self.reporter logger:nil processUnderTestEnvironment:processEnvironment];
  NSError *error = nil;
  BOOL success = [configuration loadWithArguments:arguments workingDirectory:workingDirectory error:&error];

  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertFalse(configuration.runWithoutSimulator);
  XCTAssertFalse(configuration.listTestsOnly);
  XCTAssertNil(configuration.testFilter);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertEqualObjects(configuration.simulatorName, @"iPhone 6");
  XCTAssertNil(configuration.simulatorOS);
  XCTAssertEqualObjects(configuration.targetDeviceConfiguration.device, FBControlCoreConfiguration_Device_iPhone6.new);
}

- (void)testiOSLogicTests
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

  FBXCTestConfiguration *configuration = [[FBXCTestConfiguration alloc] initWithReporter:self.reporter logger:nil processUnderTestEnvironment:processEnvironment];
  BOOL success = [configuration loadWithArguments:arguments workingDirectory:workingDirectory error:&error];

  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertNotNil(configuration.shims);
  XCTAssertFalse(configuration.runWithoutSimulator);
  XCTAssertFalse(configuration.listTestsOnly);
  XCTAssertNil(configuration.testFilter);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertEqualObjects(configuration.simulatorName, @"iPhone 6");
  XCTAssertNil(configuration.simulatorOS);
  XCTAssertEqualObjects(configuration.targetDeviceConfiguration.device, FBControlCoreConfiguration_Device_iPhone6.new);
}

- (void)testMacLogicTests
{
  NSError *error = nil;
  if (![FBXCTestShimConfiguration findShimDirectoryWithError:&error]) {
    NSLog(@"Could not locate a shim directory, skipping -[%@ %@]. %@", NSStringFromClass(self.class), NSStringFromSelector(_cmd), error);
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [FBXCTestKitFixtures macUnitTestBundlePath];
  NSDictionary<NSString *, NSString *> *processEnvironment = @{@"FOO" : @"BAR"};
  NSArray *arguments = @[ @"run-tests", @"-sdk", @"macosx", @"-logicTest", testBundlePath];

  FBXCTestConfiguration *configuration = [[FBXCTestConfiguration alloc] initWithReporter:self.reporter logger:nil processUnderTestEnvironment:processEnvironment];
  BOOL success = [configuration loadWithArguments:arguments workingDirectory:workingDirectory error:&error];

  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertNotNil(configuration.shims);
  XCTAssertTrue(configuration.runWithoutSimulator);
  XCTAssertFalse(configuration.listTestsOnly);
  XCTAssertNil(configuration.testFilter);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertNil(configuration.simulatorName);
  XCTAssertNil(configuration.simulatorOS);
}

- (void)testMacTestList
{
  NSError *error = nil;
  if (![FBXCTestShimConfiguration findShimDirectoryWithError:&error]) {
    NSLog(@"Could not locate a shim directory, skipping -[%@ %@]. %@", NSStringFromClass(self.class), NSStringFromSelector(_cmd), error);
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [FBXCTestKitFixtures macUnitTestBundlePath];
  NSArray *arguments = @[ @"run-tests", @"-sdk", @"macosx", @"-logicTest", testBundlePath, @"-listTestsOnly" ];

  FBXCTestConfiguration *configuration = [[FBXCTestConfiguration alloc] initWithReporter:self.reporter logger:nil processUnderTestEnvironment:@{}];
  BOOL success = [configuration loadWithArguments:arguments workingDirectory:workingDirectory error:&error];

  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertNotNil(configuration.shims);
  XCTAssertTrue(configuration.runWithoutSimulator);
  XCTAssertTrue(configuration.listTestsOnly);
  XCTAssertNil(configuration.testFilter);
  XCTAssertNil(configuration.simulatorName);
  XCTAssertNil(configuration.simulatorOS);
}

@end
