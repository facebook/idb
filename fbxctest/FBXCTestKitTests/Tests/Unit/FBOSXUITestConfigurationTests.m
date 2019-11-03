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

@interface FBOSXUITestConfigurationTests : FBControlCoreValueTestCase

@end

@implementation FBOSXUITestConfigurationTests

- (NSString *)appTestArgument
{
  NSString *testBundlePath =  FBXCTestKitFixtures.macUnitTestBundlePath;
  NSString *testHostAppPath = FBXCTestKitFixtures.macUITestAppTargetPath;
  return [NSString stringWithFormat:@"%@:%@", testBundlePath, testHostAppPath];
}

- (NSString *)uiTestArgument
{
  NSString *testBundlePath = FBXCTestKitFixtures.macUITestBundlePath;
  NSString *testHostAppPath = FBXCTestKitFixtures.macCommonAppPath;
  NSString *applicationPath = FBXCTestKitFixtures.macUITestAppTargetPath;
  return [NSString stringWithFormat:@"%@:%@:%@", testBundlePath, testHostAppPath, applicationPath];
}

- (void)testMacUITests
{
  NSError *error = nil;
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSDictionary<NSString *, NSString *> *processEnvironment = @{@"FOO" : @"BAR"};
  NSArray *arguments = @[ @"run-tests", @"-sdk", @"macosx", @"-uiTest", self.uiTestArgument];

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);
  FBXCTestConfiguration *configuration = commandLine.configuration;

  XCTAssertTrue([configuration isKindOfClass:FBTestManagerTestConfiguration.class]);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([commandLine.destination isKindOfClass:FBXCTestDestinationMacOSX.class]);
  XCTAssertEqualObjects(configuration.testType, FBXCTestTypeUITest);

  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestCommandLine *expected = [FBXCTestCommandLine
    commandLineWithConfiguration:[FBTestManagerTestConfiguration
      configurationWithShims:configuration.shims
      environment:processEnvironment
      workingDirectory:workingDirectory
      testBundlePath:FBXCTestKitFixtures.macUITestBundlePath
      waitForDebugger:NO
      timeout:0
      runnerAppPath:FBXCTestKitFixtures.macCommonAppPath
      testTargetAppPath:FBXCTestKitFixtures.macUITestAppTargetPath
      testFilter:nil
      videoRecordingPath:nil
      testArtifactsFilenameGlobs:nil
      osLogPath:nil]
    destination:[[FBXCTestDestinationMacOSX alloc] init]
  ];
  XCTAssertEqualObjects(commandLine, expected);
}

- (void)testMacUITestsIgnoresDestination
{
  NSError *error = nil;
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSDictionary<NSString *, NSString *> *processEnvironment = @{@"FOO" : @"BAR"};
  NSArray *arguments = @[ @"run-tests", @"-sdk", @"macosx", @"-destination", @"name=iPhone 6", @"-uiTest", self.uiTestArgument];

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);
  FBXCTestConfiguration *configuration = commandLine.configuration;

  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([commandLine.destination isKindOfClass:FBXCTestDestinationMacOSX.class]);
  XCTAssertEqualObjects(configuration.testType, FBXCTestTypeUITest);

  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestCommandLine *expected = [FBXCTestCommandLine
    commandLineWithConfiguration:[FBTestManagerTestConfiguration
      configurationWithShims:configuration.shims
      environment:processEnvironment
      workingDirectory:workingDirectory
      testBundlePath:FBXCTestKitFixtures.macUITestBundlePath
      waitForDebugger:NO
      timeout:0
      runnerAppPath:FBXCTestKitFixtures.macCommonAppPath
      testTargetAppPath:FBXCTestKitFixtures.macUITestAppTargetPath
      testFilter:nil
      videoRecordingPath:nil
      testArtifactsFilenameGlobs:nil
      osLogPath:nil]
    destination:[[FBXCTestDestinationMacOSX alloc] init]];
  XCTAssertEqualObjects(commandLine, expected);
}

- (void)testMacApplicationTests
{
  NSError *error = nil;
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSDictionary<NSString *, NSString *> *processEnvironment = @{@"FOO" : @"BAR"};
  NSArray *arguments = @[ @"run-tests", @"-sdk", @"macosx", @"-appTest", self.appTestArgument];

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);
  FBXCTestConfiguration *configuration = commandLine.configuration;

  XCTAssertTrue([configuration isKindOfClass:FBTestManagerTestConfiguration.class]);
  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([commandLine.destination isKindOfClass:FBXCTestDestinationMacOSX.class]);
  XCTAssertEqualObjects(configuration.testType, FBXCTestTypeApplicationTest);

  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestCommandLine *expected = [FBXCTestCommandLine
    commandLineWithConfiguration:[FBTestManagerTestConfiguration
      configurationWithShims:configuration.shims
      environment:processEnvironment
      workingDirectory:workingDirectory
      testBundlePath:FBXCTestKitFixtures.macUnitTestBundlePath
      waitForDebugger:NO
      timeout:0
      runnerAppPath:FBXCTestKitFixtures.macCommonAppPath
      testTargetAppPath:nil
      testFilter:nil
      videoRecordingPath:nil
      testArtifactsFilenameGlobs:nil
      osLogPath:nil]
    destination:[[FBXCTestDestinationMacOSX alloc] init]];
  XCTAssertEqualObjects(commandLine, expected);
}

- (void)testMacApplicationTestsIgnoresDestination
{
  NSError *error = nil;
  NSString *workingDirectory = [FBXCTestKitFixtures createTemporaryDirectory];
  NSDictionary<NSString *, NSString *> *processEnvironment = @{@"FOO" : @"BAR"};
  NSArray *arguments = @[ @"run-tests", @"-sdk", @"macosx", @"-destination", @"name=iPhone 6", @"-appTest", self.appTestArgument];

  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine commandLineFromArguments:arguments processUnderTestEnvironment:processEnvironment workingDirectory:workingDirectory error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(commandLine);
  FBXCTestConfiguration *configuration = commandLine.configuration;

  XCTAssertEqualObjects(configuration.processUnderTestEnvironment, processEnvironment);
  XCTAssertTrue([commandLine.destination isKindOfClass:FBXCTestDestinationMacOSX.class]);
  XCTAssertEqualObjects(configuration.testType, FBXCTestTypeApplicationTest);

  [self assertValueSemanticsOfConfiguration:configuration];

  FBXCTestCommandLine *expected = [FBXCTestCommandLine
    commandLineWithConfiguration:[FBTestManagerTestConfiguration
      configurationWithShims:configuration.shims
      environment:processEnvironment
      workingDirectory:workingDirectory
      testBundlePath:FBXCTestKitFixtures.macUnitTestBundlePath
      waitForDebugger:NO
      timeout:0
      runnerAppPath:FBXCTestKitFixtures.macCommonAppPath
      testTargetAppPath:nil
      testFilter:nil
      videoRecordingPath:nil
      testArtifactsFilenameGlobs:nil
      osLogPath:nil]
    destination:[[FBXCTestDestinationMacOSX alloc] init]];
  XCTAssertEqualObjects(commandLine, expected);
}

@end
