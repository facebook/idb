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

@interface FBOSXLogicTestConfigurationTests : FBControlCoreValueTestCase

@end

@implementation FBOSXLogicTestConfigurationTests

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

  FBXCTestConfiguration *configuration = [FBXCTestConfiguration configurationFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];

  XCTAssertNil(error);
  XCTAssertNotNil(configuration);
  XCTAssertNotNil(configuration.shims);
  XCTAssertTrue([configuration isKindOfClass:FBLogicTestConfiguration.class]);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([configuration.destination isKindOfClass:FBXCTestDestinationMacOSX.class]);
  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestConfiguration *expected = [FBLogicTestConfiguration
    configurationWithDestination:[[FBXCTestDestinationMacOSX alloc] init]
    shims:configuration.shims
    environment:processEnvironment
    workingDirectory:workingDirectory
    testBundlePath:testBundlePath
    waitForDebugger:NO
    timeout:0
    testFilter:nil];
  XCTAssertEqualObjects(configuration, expected);
}

- (void)testMacLogicTestsIgnoresDestination
{
  NSError *error = nil;
  if (![FBXCTestShimConfiguration findShimDirectoryWithError:&error]) {
    NSLog(@"Could not locate a shim directory, skipping -[%@ %@]. %@", NSStringFromClass(self.class), NSStringFromSelector(_cmd), error);
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [FBXCTestKitFixtures macUnitTestBundlePath];
  NSDictionary<NSString *, NSString *> *processEnvironment = @{@"FOO" : @"BAR"};
  NSArray *arguments = @[ @"run-tests", @"-sdk", @"macosx", @"-destination", @"name=iPhone 6", @"-logicTest", testBundlePath];

  FBXCTestConfiguration *configuration = [FBXCTestConfiguration configurationFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];

  XCTAssertNil(error);
  XCTAssertNotNil(configuration);
  XCTAssertNotNil(configuration.shims);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([configuration.destination isKindOfClass:FBXCTestDestinationMacOSX.class]);
  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestConfiguration *expected = [FBLogicTestConfiguration
    configurationWithDestination:[[FBXCTestDestinationMacOSX alloc] init]
    shims:configuration.shims
    environment:processEnvironment
    workingDirectory:workingDirectory
    testBundlePath:testBundlePath
    waitForDebugger:NO
    timeout:0
    testFilter:nil];
  XCTAssertEqualObjects(configuration, expected);
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

  FBXCTestConfiguration *configuration = [FBXCTestConfiguration configurationFromArguments:arguments processUnderTestEnvironment:@{} workingDirectory:workingDirectory error:&error];

  XCTAssertNil(error);
  XCTAssertNotNil(configuration);
  XCTAssertNotNil(configuration.shims);
  XCTAssertTrue([configuration.destination isKindOfClass:FBXCTestDestinationMacOSX.class]);
  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestConfiguration *expected = [FBListTestConfiguration
    configurationWithDestination:[[FBXCTestDestinationMacOSX alloc] init]
    shims:configuration.shims
    environment:@{}
    workingDirectory:workingDirectory
    testBundlePath:testBundlePath
    waitForDebugger:NO
    timeout:0];
  XCTAssertEqualObjects(configuration, expected);
}

- (void)testMacTestListIgnoresDestination
{
  NSError *error = nil;
  if (![FBXCTestShimConfiguration findShimDirectoryWithError:&error]) {
    NSLog(@"Could not locate a shim directory, skipping -[%@ %@]. %@", NSStringFromClass(self.class), NSStringFromSelector(_cmd), error);
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [FBXCTestKitFixtures macUnitTestBundlePath];
  NSArray *arguments = @[ @"run-tests", @"-sdk", @"macosx", @"-destination", @"name=iPhone 6", @"-logicTest", testBundlePath, @"-listTestsOnly" ];

  FBXCTestConfiguration *configuration = [FBXCTestConfiguration configurationFromArguments:arguments processUnderTestEnvironment:@{} workingDirectory:workingDirectory error:&error];

  XCTAssertNil(error);
  XCTAssertNotNil(configuration);
  XCTAssertNotNil(configuration.shims);
  XCTAssertTrue([configuration.destination isKindOfClass:FBXCTestDestinationMacOSX.class]);
  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestConfiguration *expected = [FBListTestConfiguration
    configurationWithDestination:[[FBXCTestDestinationMacOSX alloc] init]
    shims:configuration.shims
    environment:@{}
    workingDirectory:workingDirectory
    testBundlePath:testBundlePath
    waitForDebugger:NO
    timeout:0];
  XCTAssertEqualObjects(configuration, expected);
}

@end
