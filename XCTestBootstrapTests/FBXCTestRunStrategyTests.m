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

#import "FBDeviceOperator.h"
#import "FBTestRunnerConfiguration.h"
#import "FBXCTestPreparationStrategy.h"
#import "FBXCTestRunStrategy.h"

@interface FBXCTestRunStrategyTests : XCTestCase
@end

@implementation FBXCTestRunStrategyTests

- (void)testCallingStrategyWithMissingDevice
{
  id prepareTestMock = [OCMockObject niceMockForProtocol:@protocol(FBXCTestPreparationStrategy)];
  FBXCTestRunStrategy *strategy = [FBXCTestRunStrategy strategyWithDeviceOperator:nil testPrepareStrategy:prepareTestMock];
  XCTAssertThrows([strategy startTestManagerWithAttributes:nil environment:nil error:nil]);
}

- (void)testTestRunWithRequiredAttributes
{
  id prepareTestMock = [OCMockObject niceMockForProtocol:@protocol(FBXCTestPreparationStrategy)];
  FBXCTestRunStrategy *strategy = [FBXCTestRunStrategy strategyWithDeviceOperator:[OCMockObject mockForProtocol:@protocol(FBDeviceOperator)] testPrepareStrategy:prepareTestMock];
  XCTAssertNoThrow([strategy startTestManagerWithAttributes:nil environment:nil error:nil]);
}

- (void)testCallToTestPreparationStep
{
  OCMockObject<FBXCTestPreparationStrategy> *prepareTestMock = [OCMockObject mockForProtocol:@protocol(FBXCTestPreparationStrategy)];
  [[prepareTestMock expect] prepareTestWithDeviceOperator:[OCMArg any] error:[OCMArg anyObjectRef]];
  FBXCTestRunStrategy *strategy = [FBXCTestRunStrategy strategyWithDeviceOperator:[OCMockObject mockForProtocol:@protocol(FBDeviceOperator)] testPrepareStrategy:prepareTestMock];
  XCTAssertNoThrow([strategy startTestManagerWithAttributes:nil environment:nil error:nil]);
  [prepareTestMock verify];
}

- (void)testPassingArgumentAndEnvironmentVariables
{
  OCMockObject<FBDeviceOperator> *deviceOperatorMock = [OCMockObject mockForProtocol:@protocol(FBDeviceOperator)];
  [[[deviceOperatorMock expect] andReturnValue:@13] processIDWithBundleID:[OCMArg any] error:[OCMArg anyObjectRef]];
  [[[deviceOperatorMock expect] andReturnValue:@YES] launchApplicationWithBundleID:[OCMArg any] arguments:@[@4] environment:@{@"A" : @"B"} error:[OCMArg anyObjectRef]];
  [[deviceOperatorMock expect] dvtDevice];

  id testConfigurationMock = [OCMockObject niceMockForClass:FBTestRunnerConfiguration.class];

  id prepareTestMock = [OCMockObject niceMockForProtocol:@protocol(FBXCTestPreparationStrategy)];
  [[[prepareTestMock stub] andReturn:testConfigurationMock] prepareTestWithDeviceOperator:[OCMArg any] error:[OCMArg anyObjectRef]];

  FBXCTestRunStrategy *strategy = [FBXCTestRunStrategy strategyWithDeviceOperator:deviceOperatorMock testPrepareStrategy:prepareTestMock];
  XCTAssertTrue([strategy startTestManagerWithAttributes:@[@4] environment:@{@"A" : @"B"} error:nil]);
  [deviceOperatorMock verify];
}

- (void)testTestPreparationFailure
{
  OCMockObject<FBDeviceOperator> *deviceOperatorMock = [OCMockObject mockForProtocol:@protocol(FBDeviceOperator)];
  id prepareTestMock = [OCMockObject niceMockForProtocol:@protocol(FBXCTestPreparationStrategy)];
  FBXCTestRunStrategy *strategy = [FBXCTestRunStrategy strategyWithDeviceOperator:deviceOperatorMock testPrepareStrategy:prepareTestMock];
  XCTAssertFalse([strategy startTestManagerWithAttributes:nil environment:nil error:nil]);
  [deviceOperatorMock verify];
}

@end
