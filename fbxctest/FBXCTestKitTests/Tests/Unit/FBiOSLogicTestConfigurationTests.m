/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

- (BOOL)canParseLogicTests
{
  NSError *error = nil;
  if ([[FBXCTestShimConfiguration findShimDirectoryOnQueue:dispatch_get_main_queue()] await:&error]) {
    return YES;
  }
  NSLog(@"Could not locate a shim directory, skipping %@", error);
  return NO;
}

- (void)testiOSLogicTestsWithDestinationAndSDK
{
  NSError *error = nil;
  if (![self canParseLogicTests]) {
    NSLog(@"Could not locate a shim directory, skipping -[%@ %@]. %@", NSStringFromClass(self.class), NSStringFromSelector(_cmd), error);
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [self iOSUnitTestBundlePath];
  NSDictionary<NSString *, NSString *> *processEnvironment = @{@"FOO" : @"BAR"};
  NSArray<NSString *> *arguments = @[ @"run-tests", @"-sdk", @"iphonesimulator", @"-destination", @"name=iPhone 6", @"-logicTest", testBundlePath ];

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);

  FBXCTestConfiguration *configuration = commandLine.configuration;
  XCTAssertNotNil(configuration.shims);
  XCTAssertTrue([configuration isKindOfClass:FBLogicTestConfiguration.class]);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([commandLine.destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class]);
  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestCommandLine *expected = [FBXCTestCommandLine
    commandLineWithConfiguration:[FBLogicTestConfiguration
      configurationWithShims:configuration.shims
      environment:processEnvironment
      workingDirectory:workingDirectory
      testBundlePath:self.iOSUnitTestBundlePath
      waitForDebugger:NO
      timeout:0
      testFilter:nil
      mirroring:FBLogicTestMirrorFileLogs]
    destination:[[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:FBDeviceModeliPhone6 version:nil]];
  XCTAssertEqualObjects(commandLine, expected);
}

- (void)testiOSLogicTestsWithDestinationWithoutSDK
{
  NSError *error = nil;
  if (![self canParseLogicTests]) {
    NSLog(@"Could not locate a shim directory, skipping -[%@ %@]. %@", NSStringFromClass(self.class), NSStringFromSelector(_cmd), error);
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [self iOSUnitTestBundlePath];
  NSDictionary<NSString *, NSString *> *processEnvironment = @{@"FOO" : @"BAR"};
  NSArray<NSString *> *arguments = @[ @"run-tests", @"-destination", @"name=iPhone 6", @"-logicTest", testBundlePath ];

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);
  FBXCTestConfiguration *configuration = commandLine.configuration;

  XCTAssertNotNil(configuration);
  XCTAssertNotNil(configuration.shims);
  XCTAssertTrue([configuration isKindOfClass:FBLogicTestConfiguration.class]);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([commandLine.destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class]);
  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestCommandLine *expected = [FBXCTestCommandLine
    commandLineWithConfiguration:[FBLogicTestConfiguration
      configurationWithShims:configuration.shims
      environment:processEnvironment
      workingDirectory:workingDirectory
      testBundlePath:self.iOSUnitTestBundlePath
      waitForDebugger:NO
      timeout:0
      testFilter:nil
      mirroring:FBLogicTestMirrorFileLogs]
    destination:[[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:FBDeviceModeliPhone6 version:nil]];
  XCTAssertEqualObjects(commandLine, expected);

}

- (void)testiOSLogicTestsWithSDKWithoutDestination
{
  NSError *error = nil;
  if (![self canParseLogicTests]) {
    NSLog(@"Could not locate a shim directory, skipping -[%@ %@]. %@", NSStringFromClass(self.class), NSStringFromSelector(_cmd), error);
    return;
  }

  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSString *testBundlePath = [self iOSUnitTestBundlePath];
  NSDictionary<NSString *, NSString *> *processEnvironment = @{@"FOO" : @"BAR"};
  NSArray<NSString *> *arguments = @[ @"run-tests", @"-sdk", @"iphonesimulator", @"-logicTest", testBundlePath ];

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);
  FBXCTestConfiguration *configuration = commandLine.configuration;

  XCTAssertNil(error);
  XCTAssertNotNil(configuration);
  XCTAssertNotNil(configuration.shims);
  XCTAssertTrue([configuration isKindOfClass:FBLogicTestConfiguration.class]);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([commandLine.destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class]);
  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestCommandLine *expected = [FBXCTestCommandLine
    commandLineWithConfiguration:[FBLogicTestConfiguration
      configurationWithShims:configuration.shims
      environment:processEnvironment
      workingDirectory:workingDirectory
      testBundlePath:self.iOSUnitTestBundlePath
      waitForDebugger:NO
      timeout:0
      testFilter:nil
      mirroring:FBLogicTestMirrorFileLogs]
    destination:[[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:nil version:nil]];
  XCTAssertEqualObjects(commandLine, expected);
}

@end
