/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <OCMock/OCMock.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

@interface FBXCTestRunStrategyTests : XCTestCase

@property (nonatomic, strong, readwrite) FBApplicationLaunchConfiguration *applicationLaunchConfiguration;
@property (nonatomic, strong, readwrite) OCMockObject *testManagerMock;

@end

@implementation FBXCTestRunStrategyTests

- (void)setUp
{
  [super setUp];

  self.applicationLaunchConfiguration = [FBApplicationLaunchConfiguration configurationWithBundleID:@"com.foo.Bar" bundleName:@"Bar" arguments:@[] environment:@{} waitForDebugger:NO output:FBProcessOutputConfiguration.outputToDevNull];
  self.testManagerMock = [OCMockObject niceMockForClass:FBTestManager.class];
  [[[self.testManagerMock stub] andReturn:self.testManagerMock] testManagerWithContext:OCMArg.any iosTarget:OCMArg.any reporter:OCMArg.any logger:OCMArg.any];
  [[[[self.testManagerMock stub] ignoringNonObjectArgs] andReturn:[FBFuture futureWithResult:FBTestManagerResult.success]] connect];
}

- (void)tearDown
{
  [super tearDown];

  [self.testManagerMock stopMocking];
}

- (void)testTestRunWithRequiredAttributes
{
  id prepareTestMock = [OCMockObject niceMockForProtocol:@protocol(FBXCTestPreparationStrategy)];
  FBXCTestRunStrategy *strategy = [FBXCTestRunStrategy strategyWithIOSTarget:[OCMockObject niceMockForProtocol:@protocol(FBiOSTarget)] testPrepareStrategy:prepareTestMock reporter:nil logger:nil];
  XCTAssertNoThrow([[strategy startTestManagerWithApplicationLaunchConfiguration:self.applicationLaunchConfiguration] await:nil]);
}

- (void)testCallToTestPreparationStep
{
  OCMockObject<FBXCTestPreparationStrategy> *prepareTestMock = [OCMockObject mockForProtocol:@protocol(FBXCTestPreparationStrategy)];
  [[prepareTestMock expect] prepareTestWithIOSTarget:[OCMArg any] error:[OCMArg anyObjectRef]];
  FBXCTestRunStrategy *strategy = [FBXCTestRunStrategy strategyWithIOSTarget:[OCMockObject niceMockForProtocol:@protocol(FBiOSTarget)] testPrepareStrategy:prepareTestMock reporter:nil logger:nil];
  XCTAssertNoThrow([[strategy startTestManagerWithApplicationLaunchConfiguration:self.applicationLaunchConfiguration] await:nil]);
  [prepareTestMock verify];
}

- (void)testPassingArgumentAndEnvironmentVariables
{
  FBApplicationLaunchConfiguration *launchConfiguration = [FBApplicationLaunchConfiguration
    configurationWithBundleID:@"com.bundle"
    bundleName:@"com.bundle"
    arguments:@[@"4"]
    environment:@{@"A" : @"B"}
    waitForDebugger:NO
    output:FBProcessOutputConfiguration.outputToDevNull];

  OCMockObject<FBDeviceOperator> *deviceOperatorMock = [OCMockObject niceMockForProtocol:@protocol(FBDeviceOperator)];
  [[[deviceOperatorMock stub] andReturn:[FBFuture futureWithResult:@13]] processIDWithBundleID:[OCMArg any]];

  OCMockObject<FBiOSTarget> *iosTargetMock = [OCMockObject niceMockForProtocol:@protocol(FBiOSTarget)];
  [[[iosTargetMock stub] andReturn:deviceOperatorMock] deviceOperator];
  [[[iosTargetMock stub] andReturn:dispatch_get_main_queue()] workQueue];
  [(id<FBApplicationCommands>)[[iosTargetMock expect] andReturn:[FBFuture futureWithResult:@YES]] launchApplication:launchConfiguration];

  id testRunnerMock = [OCMockObject niceMockForClass:FBProductBundle.class];
  [[[testRunnerMock stub] andReturn:@"com.bundle"] bundleID];

  id testConfigurationMock = [OCMockObject niceMockForClass:FBTestRunnerConfiguration.class];
  [[[testConfigurationMock stub] andReturn:@[@"4"]] launchArguments];
  [[[testConfigurationMock stub] andReturn:@{@"A" : @"B"}] launchEnvironment];
  [[[testConfigurationMock stub] andReturn:testRunnerMock] testRunner];

  id prepareTestMock = [OCMockObject niceMockForProtocol:@protocol(FBXCTestPreparationStrategy)];
  [[[prepareTestMock stub] andReturn:testConfigurationMock] prepareTestWithIOSTarget:[OCMArg any] error:[OCMArg anyObjectRef]];

  FBXCTestRunStrategy *strategy = [FBXCTestRunStrategy strategyWithIOSTarget:iosTargetMock testPrepareStrategy:prepareTestMock reporter:nil logger:nil];
  XCTAssertTrue([[strategy startTestManagerWithApplicationLaunchConfiguration:[self.applicationLaunchConfiguration withEnvironment:@{@"A" : @"B"}]] await:nil]);
  [iosTargetMock verify];
}

- (void)testTestPreparationFailure
{
  OCMockObject<FBiOSTarget> *iosTargetMock = [OCMockObject niceMockForProtocol:@protocol(FBiOSTarget)];
  [[[iosTargetMock stub] andReturn:dispatch_get_main_queue()] workQueue];
  id prepareTestMock = [OCMockObject niceMockForProtocol:@protocol(FBXCTestPreparationStrategy)];
  FBXCTestRunStrategy *strategy = [FBXCTestRunStrategy strategyWithIOSTarget:iosTargetMock testPrepareStrategy:prepareTestMock reporter:nil logger:nil];
  XCTAssertFalse([[strategy startTestManagerWithApplicationLaunchConfiguration:self.applicationLaunchConfiguration] await:nil]);
  [iosTargetMock verify];
}

@end
