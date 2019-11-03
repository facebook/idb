/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
  [[[self.testManagerMock stub] andReturn:self.testManagerMock] testManagerWithContext:OCMArg.any iosTarget:OCMArg.any reporter:OCMArg.any logger:OCMArg.any testedApplicationAdditionalEnvironment:OCMArg.any];
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
  id testConfigurationMock = [OCMockObject niceMockForClass:FBTestRunnerConfiguration.class];
  OCMockObject<FBXCTestPreparationStrategy> *prepareTestMock = [OCMockObject mockForProtocol:@protocol(FBXCTestPreparationStrategy)];

  [[[prepareTestMock expect] andReturn:[FBFuture futureWithResult:testConfigurationMock]] prepareTestWithIOSTarget:[OCMArg any]];
  OCMockObject *iOSTarget = [OCMockObject niceMockForProtocol:@protocol(FBiOSTarget)];
  [[[iOSTarget stub] andReturn:dispatch_get_main_queue()] workQueue];
  [[[iOSTarget stub] andReturn:[FBFuture futureWithResult:@13]] processIDWithBundleID:OCMArg.any];
  OCMockObject<FBLaunchedProcess> *processMock = [OCMockObject niceMockForProtocol:@protocol(FBLaunchedProcess)];
  [(id<FBApplicationCommands>)[[iOSTarget stub] andReturn:[FBFuture futureWithResult:processMock]] launchApplication:[OCMArg any]];

  FBXCTestRunStrategy *strategy = [FBXCTestRunStrategy strategyWithIOSTarget:(id)iOSTarget testPrepareStrategy:prepareTestMock reporter:nil logger:nil];
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

  OCMockObject<FBiOSTarget> *iosTargetMock = [OCMockObject niceMockForProtocol:@protocol(FBiOSTarget)];
  [[[iosTargetMock stub] andReturn:dispatch_get_main_queue()] workQueue];
  [[[iosTargetMock stub] andReturn:[FBFuture futureWithResult:@13]] processIDWithBundleID:OCMArg.any];
  OCMockObject<FBLaunchedProcess> *processMock = [OCMockObject niceMockForProtocol:@protocol(FBLaunchedProcess)];
  [(id<FBApplicationCommands>)[[iosTargetMock expect] andReturn:[FBFuture futureWithResult:processMock]] launchApplication:launchConfiguration];

  id testRunnerMock = [OCMockObject niceMockForClass:FBProductBundle.class];
  [[[testRunnerMock stub] andReturn:@"com.bundle"] bundleID];

  id testConfigurationMock = [OCMockObject niceMockForClass:FBTestRunnerConfiguration.class];
  [[[testConfigurationMock stub] andReturn:@[@"4"]] launchArguments];
  [[[testConfigurationMock stub] andReturn:@{@"A" : @"B"}] launchEnvironment];
  [[[testConfigurationMock stub] andReturn:testRunnerMock] testRunner];

  id prepareTestMock = [OCMockObject niceMockForProtocol:@protocol(FBXCTestPreparationStrategy)];
  [[[prepareTestMock stub] andReturn:[FBFuture futureWithResult:testConfigurationMock]] prepareTestWithIOSTarget:[OCMArg any]];

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
