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
  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);
  FBXCTestConfiguration *configuration = commandLine.configuration;

  XCTAssertTrue([configuration isKindOfClass:FBTestManagerTestConfiguration.class]);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([commandLine.destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class]);
  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestCommandLine *expected = [FBXCTestCommandLine
    commandLineWithConfiguration:[FBTestManagerTestConfiguration
      configurationWithShims:configuration.shims
      environment:processEnvironment
      workingDirectory:workingDirectory
      testBundlePath:self.iOSUITestBundlePath
      waitForDebugger:NO
      timeout:0
      runnerAppPath:FBXCTestKitFixtures.tableSearchApplicationPath
      testTargetAppPath:FBXCTestKitFixtures.iOSUITestAppTargetPath
      testFilter:nil
      videoRecordingPath:nil
      testArtifactsFilenameGlobs:nil
      osLogPath:nil]
    destination:[[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:FBDeviceModeliPhone6 version:nil]];
  XCTAssertEqualObjects(commandLine, expected);
}

- (void)testiOSApplicationTestWithDestinationWithoutSDK
{
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSDictionary<NSString *, NSString *> *processEnvironment = @{@"FOO" : @"BAR"};
  NSArray<NSString *> *arguments = @[ @"run-tests", @"-destination", @"name=iPhone 6", @"-uiTest", self.appTestArgument ];

  NSError *error = nil;
  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);
  FBXCTestConfiguration *configuration = commandLine.configuration;

  XCTAssertTrue([configuration isKindOfClass:FBTestManagerTestConfiguration.class]);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([commandLine.destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class]);
  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestCommandLine *expected = [FBXCTestCommandLine
    commandLineWithConfiguration:[FBTestManagerTestConfiguration
      configurationWithShims:configuration.shims
      environment:processEnvironment
      workingDirectory:workingDirectory
      testBundlePath:self.iOSUITestBundlePath
      waitForDebugger:NO
      timeout:0
      runnerAppPath:FBXCTestKitFixtures.tableSearchApplicationPath
      testTargetAppPath:FBXCTestKitFixtures.iOSUITestAppTargetPath
      testFilter:nil
      videoRecordingPath:nil
      testArtifactsFilenameGlobs:nil
      osLogPath:nil]
    destination:[[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:FBDeviceModeliPhone6 version:nil]];
  XCTAssertEqualObjects(commandLine, expected);
}

- (void)testiOSApplicationTestsWithSDKWithoutDestination
{
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSDictionary<NSString *, NSString *> *processEnvironment = @{@"FOO" : @"BAR"};
  NSArray<NSString *> *arguments = @[ @"run-tests", @"-sdk", @"iphonesimulator", @"-uiTest", self.appTestArgument ];

  NSError *error = nil;
  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);
  FBXCTestConfiguration *configuration = commandLine.configuration;

  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([commandLine.destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class]);
  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestCommandLine *expected = [FBXCTestCommandLine
    commandLineWithConfiguration:[FBTestManagerTestConfiguration
      configurationWithShims:configuration.shims
      environment:processEnvironment
      workingDirectory:workingDirectory
      testBundlePath:self.iOSUITestBundlePath
      waitForDebugger:NO
      timeout:0
      runnerAppPath:FBXCTestKitFixtures.tableSearchApplicationPath
      testTargetAppPath:FBXCTestKitFixtures.iOSUITestAppTargetPath
      testFilter:nil
      videoRecordingPath:nil
      testArtifactsFilenameGlobs:nil
      osLogPath:nil]
    destination:[[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:nil version:nil]];
  XCTAssertEqualObjects(commandLine, expected);
}

- (void)testiOSApplicationTestsWithoutRunTestsAtStart
{
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSDictionary<NSString *, NSString *> *processEnvironment = @{@"FOO" : @"BAR"};
  NSArray *arguments = @[ @"-reporter", @"json-stream", @"-sdk", @"iphonesimulator", @"run-tests", @"-uiTest", self.appTestArgument];

  NSError *error = nil;
  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);
  FBXCTestConfiguration *configuration = commandLine.configuration;

  XCTAssertFalse([configuration isKindOfClass:FBListTestConfiguration.class]);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([commandLine.destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class]);
  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestCommandLine *expected = [FBXCTestCommandLine
    commandLineWithConfiguration:[FBTestManagerTestConfiguration
      configurationWithShims:configuration.shims
      environment:processEnvironment
      workingDirectory:workingDirectory
      testBundlePath:self.iOSUITestBundlePath
      waitForDebugger:NO
      timeout:0
      runnerAppPath:FBXCTestKitFixtures.tableSearchApplicationPath
      testTargetAppPath:FBXCTestKitFixtures.iOSUITestAppTargetPath
      testFilter:nil
      videoRecordingPath:nil
      testArtifactsFilenameGlobs:nil
      osLogPath:nil]
    destination:[[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:nil version:nil]];
  XCTAssertEqualObjects(commandLine, expected);
}

@end
