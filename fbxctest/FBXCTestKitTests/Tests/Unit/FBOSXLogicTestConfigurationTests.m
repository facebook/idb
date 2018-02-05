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

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);
  FBXCTestConfiguration *configuration = commandLine.configuration;

  XCTAssertNotNil(configuration.shims);
  XCTAssertTrue([configuration isKindOfClass:FBLogicTestConfiguration.class]);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([commandLine.destination isKindOfClass:FBXCTestDestinationMacOSX.class]);
  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestCommandLine *expected = [FBXCTestCommandLine
    commandLineWithConfiguration:[FBLogicTestConfiguration
      configurationWithShims:configuration.shims
      environment:processEnvironment
      workingDirectory:workingDirectory
      testBundlePath:testBundlePath
      waitForDebugger:NO
      timeout:0
      testFilter:nil
      mirroring:FBLogicTestMirrorFileLogs]
    destination:[[FBXCTestDestinationMacOSX alloc] init]];
  XCTAssertEqualObjects(commandLine, expected);
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

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);
  FBXCTestConfiguration *configuration = commandLine.configuration;

  XCTAssertNotNil(configuration.shims);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([commandLine.destination isKindOfClass:FBXCTestDestinationMacOSX.class]);
  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestCommandLine *expected = [FBXCTestCommandLine
    commandLineWithConfiguration:[FBLogicTestConfiguration
      configurationWithShims:configuration.shims
      environment:processEnvironment
      workingDirectory:workingDirectory
      testBundlePath:testBundlePath
      waitForDebugger:NO
      timeout:0
      testFilter:nil
      mirroring:FBLogicTestMirrorFileLogs]
    destination:[[FBXCTestDestinationMacOSX alloc] init]];
  XCTAssertEqualObjects(commandLine, expected);
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

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:@{} workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);
  FBXCTestConfiguration *configuration = commandLine.configuration;

  XCTAssertNotNil(configuration.shims);
  XCTAssertTrue([commandLine.destination isKindOfClass:FBXCTestDestinationMacOSX.class]);
  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestCommandLine *expected = [FBXCTestCommandLine
    commandLineWithConfiguration:[FBListTestConfiguration
      configurationWithShims:configuration.shims
      environment:@{}
      workingDirectory:workingDirectory
      testBundlePath:testBundlePath
      waitForDebugger:NO
      timeout:0]
    destination:[[FBXCTestDestinationMacOSX alloc] init]];
  XCTAssertEqualObjects(commandLine, expected);
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

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:@{} workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);
  FBXCTestConfiguration *configuration = commandLine.configuration;

  XCTAssertNotNil(configuration.shims);
  XCTAssertTrue([commandLine.destination isKindOfClass:FBXCTestDestinationMacOSX.class]);
  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestCommandLine *expected = [FBXCTestCommandLine
    commandLineWithConfiguration:[FBListTestConfiguration
      configurationWithShims:configuration.shims
      environment:@{}
      workingDirectory:workingDirectory
      testBundlePath:testBundlePath
      waitForDebugger:NO
      timeout:0]
    destination:[[FBXCTestDestinationMacOSX alloc] init]];
  XCTAssertEqualObjects(commandLine, expected);
}

@end
