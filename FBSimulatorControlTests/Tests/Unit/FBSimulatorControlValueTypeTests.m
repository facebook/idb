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

@interface FBSimulatorControlValueTypeTests : FBControlCoreValueTestCase

@end

@implementation FBSimulatorControlValueTypeTests

- (void)testAppLaunchConfigurations
{
  NSArray<FBApplicationLaunchConfiguration *> *values = @[
    self.appLaunch1,
    self.appLaunch2,
  ];
  [self assertEqualityOfCopy:values];
  [self assertUnarchiving:values];
  [self assertJSONSerialization:values];
  [self assertJSONDeserialization:values];
}

- (void)testAgentLaunchLaunchConfigurations
{
  NSArray<FBAgentLaunchConfiguration *> *values = @[
    self.agentLaunch1,
  ];
  [self assertEqualityOfCopy:values];
  [self assertUnarchiving:values];
  [self assertJSONSerialization:values];
  [self assertJSONDeserialization:values];
}

- (void)testAgentLaunchConfigurations
{
  NSArray<FBAgentLaunchConfiguration *> *values = @[self.agentLaunch1];
  [self assertEqualityOfCopy:values];
  [self assertUnarchiving:values];
  [self assertJSONSerialization:values];
}

- (void)testSimulatorConfigurations
{
  NSArray<FBSimulatorConfiguration *> *values = @[
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
  NSArray<FBSimulatorControlConfiguration *> *values = @[
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
  NSArray<FBSimulatorLaunchConfiguration *> *values = @[
    [[[FBSimulatorLaunchConfiguration
      withLocalizationOverride:[FBLocalizationOverride withLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]]]
      withOptions:FBSimulatorLaunchOptionsEnableDirectLaunch]
      scale75Percent],
    [[FBSimulatorLaunchConfiguration
      withOptions:FBSimulatorLaunchOptionsUseNSWorkspace]
      scale25Percent]
  ];
  [self assertEqualityOfCopy:values];
  [self assertUnarchiving:values];
  [self assertJSONSerialization:values];
}

- (void)testLaunchConfigurationScaleAppliedToFramebufferConfiguration
{
  FBSimulatorLaunchConfiguration *launchConfiguration = [[[FBSimulatorLaunchConfiguration
    withLocalizationOverride:[FBLocalizationOverride withLocale:[NSLocale localeWithLocaleIdentifier:@"en_US"]]]
    withOptions:FBSimulatorLaunchOptionsEnableDirectLaunch]
    withFramebuffer:FBFramebufferConfiguration.defaultConfiguration];
  XCTAssertNotNil(launchConfiguration.framebuffer);
  XCTAssertNil(launchConfiguration.scale);
  XCTAssertNil(launchConfiguration.scale);

  launchConfiguration = [launchConfiguration scale75Percent];
  XCTAssertEqualObjects(launchConfiguration.scale, FBSimulatorScale_75.new);
  XCTAssertEqualObjects(launchConfiguration.framebuffer.scale, FBSimulatorScale_75.new);
  XCTAssertNotEqualObjects(launchConfiguration.scale, FBSimulatorScale_50.new);
  XCTAssertNotEqualObjects(launchConfiguration.framebuffer.scale, FBSimulatorScale_50.new);
}

- (void)testFramebufferConfigurations
{
  NSArray<FBFramebufferConfiguration *> *values = @[
    FBFramebufferConfiguration.prudentConfiguration,
    FBFramebufferConfiguration.defaultConfiguration,
    [[[FBFramebufferConfiguration withVideoOptions:FBFramebufferVideoOptionsAutorecord | FBFramebufferVideoOptionsFinalFrame ] withRoundingMethod:kCMTimeRoundingMethod_RoundTowardZero] withFileType:@"foo"],
    [[[FBFramebufferConfiguration withVideoOptions:FBFramebufferVideoOptionsImmediateFrameStart] withRoundingMethod:kCMTimeRoundingMethod_RoundTowardNegativeInfinity] withFileType:@"bar"]
  ];
  [self assertEqualityOfCopy:values];
  [self assertUnarchiving:values];
  [self assertJSONSerialization:values];
}

- (void)testDiagnosticQueries
{
  NSArray<FBDiagnosticQuery *> *values = @[
    [FBDiagnosticQuery all],
    [FBDiagnosticQuery named:@[@"foo", @"bar", @"baz"]],
    [FBDiagnosticQuery filesInApplicationOfBundleID:@"foo.bar.baz" withFilenames:@[@"foo.txt", @"bar.log"]],
    [FBDiagnosticQuery crashesOfType:FBCrashLogInfoProcessTypeCustomAgent | FBCrashLogInfoProcessTypeApplication since:[NSDate dateWithTimeIntervalSince1970:100]],
  ];
  [self assertEqualityOfCopy:values];
  [self assertUnarchiving:values];
  [self assertJSONSerialization:values];
  [self assertJSONDeserialization:values];
}

@end
