/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

@interface FBTestLaunchConfigurationTests : XCTestCase
@end

@implementation FBTestLaunchConfigurationTests
{
  FBApplicationLaunchConfiguration *_appLaunch;
  FBBundleDescriptor *_testBundle;
  FBBundleDescriptor *_hostBundle;
  FBBundleDescriptor *_targetAppBundle;
}

- (void)setUp
{
  [super setUp];
  _testBundle = [[FBBundleDescriptor alloc] initWithName:@"TestBundle.xctest" identifier:@"TestBundle.xctest" path:@"/tmp/TestBundle.xctest" binary:nil];
  _hostBundle = [[FBBundleDescriptor alloc] initWithName:@"HostApp.app" identifier:@"HostApp.app" path:@"/tmp/HostApp.app" binary:nil];
  _targetAppBundle = [[FBBundleDescriptor alloc] initWithName:@"TargetApp.app" identifier:@"TargetApp.app" path:@"/tmp/TargetApp.app" binary:nil];
  _appLaunch = [[FBApplicationLaunchConfiguration alloc]
    initWithBundleID:@"com.test.app"
    bundleName:@"TestApp"
    arguments:@[]
    environment:@{}
    waitForDebugger:NO
    io:FBProcessIO.outputToDevNull
    launchMode:FBApplicationLaunchModeFailIfRunning];
}

#pragma mark - Helpers

- (FBTestLaunchConfiguration *)configWithTestHostBundle:(FBBundleDescriptor *)testHostBundle
                                                timeout:(NSTimeInterval)timeout
                                   initializeUITesting:(BOOL)initializeUITesting
                                         useXcodebuild:(BOOL)useXcodebuild
                                            testsToRun:(NSSet<NSString *> *)testsToRun
                                 coverageDirectoryPath:(NSString *)coverageDirectoryPath
                                      logDirectoryPath:(NSString *)logDirectoryPath
                                    reportResultBundle:(BOOL)reportResultBundle
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundle:_testBundle
    applicationLaunchConfiguration:_appLaunch
    testHostBundle:testHostBundle
    timeout:timeout
    initializeUITesting:initializeUITesting
    useXcodebuild:useXcodebuild
    testsToRun:testsToRun
    testsToSkip:[NSSet setWithObject:@"SomeClass/testSkipped"]
    targetApplicationBundle:_targetAppBundle
    xcTestRunProperties:@{@"key" : @"value"}
    resultBundlePath:@"/tmp/results"
    reportActivities:YES
    coverageDirectoryPath:coverageDirectoryPath
    enableContinuousCoverageCollection:YES
    logDirectoryPath:logDirectoryPath
    reportResultBundle:reportResultBundle];
}

- (FBTestLaunchConfiguration *)defaultConfig
{
  return [self configWithTestHostBundle:_hostBundle
                                timeout:120.0
                   initializeUITesting:YES
                         useXcodebuild:NO
                            testsToRun:[NSSet setWithObject:@"SomeClass/testMethod"]
                 coverageDirectoryPath:@"/tmp/coverage"
                      logDirectoryPath:@"/tmp/logs"
                    reportResultBundle:YES];
}

- (FBTestLaunchConfiguration *)minimalConfig
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundle:_testBundle
    applicationLaunchConfiguration:_appLaunch
    testHostBundle:nil
    timeout:0
    initializeUITesting:NO
    useXcodebuild:NO
    testsToRun:nil
    testsToSkip:nil
    targetApplicationBundle:nil
    xcTestRunProperties:nil
    resultBundlePath:nil
    reportActivities:NO
    coverageDirectoryPath:nil
    enableContinuousCoverageCollection:NO
    logDirectoryPath:nil
    reportResultBundle:NO];
}

#pragma mark - Equality

- (void)testIsEqual_WhenIdenticalConfigs_ReturnsYES
{
  FBTestLaunchConfiguration *configA = [self defaultConfig];
  FBTestLaunchConfiguration *configB = [self defaultConfig];
  XCTAssertEqualObjects(configA, configB, @"Identical configurations should be equal");
}

- (void)testIsEqual_WhenBothNilOptionals_ReturnsYES
{
  FBTestLaunchConfiguration *configA = [self minimalConfig];
  FBTestLaunchConfiguration *configB = [self minimalConfig];
  XCTAssertEqualObjects(configA, configB, @"Two minimal configs with nil optionals should be equal");
}

- (void)testIsEqual_WhenDifferentClass_ReturnsNO
{
  FBTestLaunchConfiguration *config = [self defaultConfig];
  XCTAssertFalse([config isEqual:@"not a config"], @"Should not be equal to a different class");
}

- (void)testIsEqual_WhenSingleFieldDiffers_ReturnsNO
{
  FBTestLaunchConfiguration *baseline = [self defaultConfig];
  NSSet<NSString *> *baseTestsToRun = [NSSet setWithObject:@"SomeClass/testMethod"];

  // Different timeout
  XCTAssertNotEqualObjects(baseline,
    [self configWithTestHostBundle:_hostBundle timeout:999.0 initializeUITesting:YES useXcodebuild:NO testsToRun:baseTestsToRun coverageDirectoryPath:@"/tmp/coverage" logDirectoryPath:@"/tmp/logs" reportResultBundle:YES],
    @"Different timeout should break equality");

  // Different initializeUITesting
  XCTAssertNotEqualObjects(baseline,
    [self configWithTestHostBundle:_hostBundle timeout:120.0 initializeUITesting:NO useXcodebuild:NO testsToRun:baseTestsToRun coverageDirectoryPath:@"/tmp/coverage" logDirectoryPath:@"/tmp/logs" reportResultBundle:YES],
    @"Different initializeUITesting should break equality");

  // Different useXcodebuild
  XCTAssertNotEqualObjects(baseline,
    [self configWithTestHostBundle:_hostBundle timeout:120.0 initializeUITesting:YES useXcodebuild:YES testsToRun:baseTestsToRun coverageDirectoryPath:@"/tmp/coverage" logDirectoryPath:@"/tmp/logs" reportResultBundle:YES],
    @"Different useXcodebuild should break equality");

  // Different testsToRun
  XCTAssertNotEqualObjects(baseline,
    [self configWithTestHostBundle:_hostBundle timeout:120.0 initializeUITesting:YES useXcodebuild:NO testsToRun:[NSSet setWithObject:@"Other/test"] coverageDirectoryPath:@"/tmp/coverage" logDirectoryPath:@"/tmp/logs" reportResultBundle:YES],
    @"Different testsToRun should break equality");

  // Different coverageDirectoryPath
  XCTAssertNotEqualObjects(baseline,
    [self configWithTestHostBundle:_hostBundle timeout:120.0 initializeUITesting:YES useXcodebuild:NO testsToRun:baseTestsToRun coverageDirectoryPath:@"/tmp/other" logDirectoryPath:@"/tmp/logs" reportResultBundle:YES],
    @"Different coverageDirectoryPath should break equality");

  // Different logDirectoryPath
  XCTAssertNotEqualObjects(baseline,
    [self configWithTestHostBundle:_hostBundle timeout:120.0 initializeUITesting:YES useXcodebuild:NO testsToRun:baseTestsToRun coverageDirectoryPath:@"/tmp/coverage" logDirectoryPath:@"/tmp/other" reportResultBundle:YES],
    @"Different logDirectoryPath should break equality");

  // Different reportResultBundle
  XCTAssertNotEqualObjects(baseline,
    [self configWithTestHostBundle:_hostBundle timeout:120.0 initializeUITesting:YES useXcodebuild:NO testsToRun:baseTestsToRun coverageDirectoryPath:@"/tmp/coverage" logDirectoryPath:@"/tmp/logs" reportResultBundle:NO],
    @"Different reportResultBundle should break equality");

  // nil vs non-nil testHostBundle
  XCTAssertNotEqualObjects([self minimalConfig],
    [self configWithTestHostBundle:_hostBundle timeout:120.0 initializeUITesting:YES useXcodebuild:NO testsToRun:baseTestsToRun coverageDirectoryPath:@"/tmp/coverage" logDirectoryPath:@"/tmp/logs" reportResultBundle:YES],
    @"nil vs non-nil testHostBundle should break equality");
}

#pragma mark - Hash

- (void)testHash_WhenEqualObjects_ReturnsSameHash
{
  FBTestLaunchConfiguration *configA = [self defaultConfig];
  FBTestLaunchConfiguration *configB = [self defaultConfig];
  XCTAssertEqual(configA.hash, configB.hash, @"Equal objects must have the same hash");
}

- (void)testHash_WhenMinimalEqualObjects_ReturnsSameHash
{
  FBTestLaunchConfiguration *configA = [self minimalConfig];
  FBTestLaunchConfiguration *configB = [self minimalConfig];
  XCTAssertEqual(configA.hash, configB.hash, @"Equal minimal objects must have the same hash");
}

#pragma mark - Description

- (void)testDescription_ContainsKeyInformation
{
  FBTestLaunchConfiguration *config = [self defaultConfig];
  NSString *desc = config.description;

  XCTAssertTrue(desc.length > 0, @"Description should be non-empty");
  XCTAssertTrue([desc containsString:@"FBTestLaunchConfiguration"], @"Description should contain class name");
}

- (void)testDescription_WhenMinimalConfig_DoesNotCrash
{
  FBTestLaunchConfiguration *config = [self minimalConfig];
  NSString *desc = config.description;
  XCTAssertTrue(desc.length > 0, @"Description should be non-empty even with nil optionals");
  XCTAssertTrue([desc containsString:@"FBTestLaunchConfiguration"], @"Description should contain class name");
}

@end
