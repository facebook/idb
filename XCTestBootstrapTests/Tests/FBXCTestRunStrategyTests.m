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

@property (nonatomic, strong, readwrite) OCMockObject *testManagerMock;

@end

@implementation FBXCTestRunStrategyTests

- (void)setUp
{
  [super setUp];

  self.testManagerMock = [OCMockObject niceMockForClass:FBTestManager.class];
  [[[self.testManagerMock stub] andReturn:self.testManagerMock] testManagerWithContext:OCMArg.any iosTarget:OCMArg.any reporter:OCMArg.any logger:OCMArg.any];
  [[[[self.testManagerMock stub] ignoringNonObjectArgs] andReturn:nil] connectWithTimeout:0];
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
  XCTAssertNoThrow([strategy startTestManagerWithAttributes:@[] environment:@{} error:nil]);
}

- (void)testCallToTestPreparationStep
{
  OCMockObject<FBXCTestPreparationStrategy> *prepareTestMock = [OCMockObject mockForProtocol:@protocol(FBXCTestPreparationStrategy)];
  [[prepareTestMock expect] prepareTestWithIOSTarget:[OCMArg any] error:[OCMArg anyObjectRef]];
  FBXCTestRunStrategy *strategy = [FBXCTestRunStrategy strategyWithIOSTarget:[OCMockObject niceMockForProtocol:@protocol(FBiOSTarget)] testPrepareStrategy:prepareTestMock reporter:nil logger:nil];
  XCTAssertNoThrow([strategy startTestManagerWithAttributes:@[] environment:@{} error:nil]);
  [prepareTestMock verify];
}

- (void)testPassingArgumentAndEnvironmentVariables
{
  FBApplicationLaunchConfiguration *launchConfiguration = [FBApplicationLaunchConfiguration
    configurationWithBundleID:@"com.bundle"
    bundleName:@"com.bundle"
    arguments:@[@"4"]
    environment:@{@"A" : @"B"}
    output:FBProcessOutputConfiguration.outputToDevNull];

  OCMockObject<FBDeviceOperator> *deviceOperatorMock = [OCMockObject niceMockForProtocol:@protocol(FBDeviceOperator)];
  [[[deviceOperatorMock expect] andReturnValue:@13] processIDWithBundleID:[OCMArg any] error:[OCMArg anyObjectRef]];

  OCMockObject<FBiOSTarget> *iosTargetMock = [OCMockObject niceMockForProtocol:@protocol(FBiOSTarget)];
  [[[iosTargetMock stub] andReturn:deviceOperatorMock] deviceOperator];
  [[[iosTargetMock expect] andReturnValue:@YES] launchApplication:launchConfiguration error:[OCMArg anyObjectRef]];

  id testRunnerMock = [OCMockObject niceMockForClass:FBProductBundle.class];
  [[[testRunnerMock stub] andReturn:@"com.bundle"] bundleID];

  id testConfigurationMock = [OCMockObject niceMockForClass:FBTestRunnerConfiguration.class];
  [[[testConfigurationMock stub] andReturn:@[@"4"]] launchArguments];
  [[[testConfigurationMock stub] andReturn:@{@"A" : @"B"}] launchEnvironment];
  [[[testConfigurationMock stub] andReturn:testRunnerMock] testRunner];

  id prepareTestMock = [OCMockObject niceMockForProtocol:@protocol(FBXCTestPreparationStrategy)];
  [[[prepareTestMock stub] andReturn:testConfigurationMock] prepareTestWithIOSTarget:[OCMArg any] error:[OCMArg anyObjectRef]];

  FBXCTestRunStrategy *strategy = [FBXCTestRunStrategy strategyWithIOSTarget:iosTargetMock testPrepareStrategy:prepareTestMock reporter:nil logger:nil];
  XCTAssertTrue([strategy startTestManagerWithAttributes:@[] environment:@{@"A" : @"B"} error:nil]);
  [iosTargetMock verify];
  [deviceOperatorMock verify];
}

- (void)testTestPreparationFailure
{
  OCMockObject<FBiOSTarget> *iosTargetMock = [OCMockObject niceMockForProtocol:@protocol(FBiOSTarget)];
  id prepareTestMock = [OCMockObject niceMockForProtocol:@protocol(FBXCTestPreparationStrategy)];
  FBXCTestRunStrategy *strategy = [FBXCTestRunStrategy strategyWithIOSTarget:iosTargetMock testPrepareStrategy:prepareTestMock reporter:nil logger:nil];
  XCTAssertFalse([strategy startTestManagerWithAttributes:@[] environment:@{} error:nil]);
  [iosTargetMock verify];
}

@end
