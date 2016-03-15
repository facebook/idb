/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBSimulatorControlFixtures.h"
#import "FBControlCoreValueTestCase.h"

@interface FBConfigurationTests : FBControlCoreValueTestCase

@end

@implementation FBConfigurationTests

- (void)testVideoConfigurations
{
  NSArray *values = @[
    [[[FBFramebufferVideoConfiguration withOptions:FBFramebufferVideoOptionsAutorecord | FBFramebufferVideoOptionsFinalFrame ] withRoundingMethod:kCMTimeRoundingMethod_RoundTowardZero] withFileType:@"foo"],
    [[[FBFramebufferVideoConfiguration withOptions:FBFramebufferVideoOptionsImmediateFrameStart] withRoundingMethod:kCMTimeRoundingMethod_RoundTowardNegativeInfinity] withFileType:@"bar"]
  ];
  [self assertEqualityOfCopy:values];
  [self assertUnarchiving:values];
  [self assertJSONSerialization:values];
}

- (void)testAppLaunchConfigurations
{
  NSArray *values = @[
    self.appLaunch1,
    self.appLaunch2,
  ];
  [self assertEqualityOfCopy:values];
  [self assertUnarchiving:values];
  [self assertJSONSerialization:values];
  [self assertJSONDeserialization:values];
}

- (void)testAgentLaunchConfigurations
{
  NSArray *values = @[self.agentLaunch1];
  [self assertEqualityOfCopy:values];
  [self assertUnarchiving:values];
  [self assertJSONSerialization:values];
}

- (void)testSimulatorConfigurations
{
  NSArray *values = @[
    FBSimulatorConfiguration.defaultConfiguration,
    FBSimulatorConfiguration.iPhone5,
    FBSimulatorConfiguration.iPad2.iOS_8_3
  ];
  [self assertEqualityOfCopy:values];
  [self assertUnarchiving:values];
  [self assertJSONSerialization:values];
}

- (void)testControlConfigurations
{
  NSArray *values = @[
    [FBSimulatorControlConfiguration
      configurationWithDeviceSetPath:nil
      options:FBSimulatorManagementOptionsKillSpuriousSimulatorsOnFirstStart],
    [FBSimulatorControlConfiguration
      configurationWithDeviceSetPath:@"/foo/bar"
      options:FBSimulatorManagementOptionsKillAllOnFirstStart | FBSimulatorManagementOptionsKillAllOnFirstStart]
  ];
  [self assertEqualityOfCopy:values];
  [self assertUnarchiving:values];
  [self assertJSONSerialization:values];
}

- (void)testLaunchConfigurations
{
  NSArray *values = @[
    [[[FBSimulatorLaunchConfiguration
      withLocaleNamed:@"en_US"]
      withOptions:FBSimulatorLaunchOptionsShowDebugWindow]
      scale75Percent],
    [[FBSimulatorLaunchConfiguration
      withOptions:FBSimulatorLaunchOptionsUseNSWorkspace]
      scale25Percent]
  ];
  [self assertEqualityOfCopy:values];
  [self assertUnarchiving:values];
  [self assertJSONSerialization:values];
}

- (void)testDiagnosticQueries
{
  NSArray *values = @[
    [FBSimulatorDiagnosticQuery all],
    [FBSimulatorDiagnosticQuery named:@[@"foo", @"bar", @"baz"]],
    [FBSimulatorDiagnosticQuery filesInApplicationOfBundleID:@"foo.bar.baz" withFilenames:@[@"foo.txt", @"bar.log"]],
    [FBSimulatorDiagnosticQuery crashesOfType:FBCrashLogInfoProcessTypeCustomAgent | FBCrashLogInfoProcessTypeApplication since:[NSDate dateWithTimeIntervalSince1970:100]],
  ];
  [self assertEqualityOfCopy:values];
  [self assertUnarchiving:values];
  [self assertJSONSerialization:values];
  [self assertJSONDeserialization:values];
}

@end
