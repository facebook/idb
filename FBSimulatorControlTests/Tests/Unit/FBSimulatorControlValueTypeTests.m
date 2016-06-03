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

- (void)testVideoConfigurations
{
  NSArray<FBFramebufferVideoConfiguration *> *values = @[
    [[[FBFramebufferVideoConfiguration withOptions:FBFramebufferVideoOptionsAutorecord | FBFramebufferVideoOptionsFinalFrame ] withRoundingMethod:kCMTimeRoundingMethod_RoundTowardZero] withFileType:@"foo"],
    [[[FBFramebufferVideoConfiguration withOptions:FBFramebufferVideoOptionsImmediateFrameStart] withRoundingMethod:kCMTimeRoundingMethod_RoundTowardNegativeInfinity] withFileType:@"bar"]
  ];
  [self assertEqualityOfCopy:values];
  [self assertUnarchiving:values];
  [self assertJSONSerialization:values];
}

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
  NSArray<FBSimulatorDiagnosticQuery *> *values = @[
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

- (void)testSimulatorQuery
{
  NSArray *values = @[
    [[FBiOSTargetQuery udids:@[@"BA1248D3-24B2-43F5-B1CD-57DCB000D12E"]] states:[FBCollectionOperations indecesFromArray:@[@(FBSimulatorStateBooted), @(FBSimulatorStateBooting)]]],
    [FBiOSTargetQuery allSimulators],
    [FBiOSTargetQuery devices:@[FBControlCoreConfiguration_Device_iPad2.new, FBControlCoreConfiguration_Device_iPadAir.new]],
    [FBiOSTargetQuery osVersions:@[FBControlCoreConfiguration_iOS_9_0.new, FBControlCoreConfiguration_iOS_9_1.new]],
    [FBiOSTargetQuery states:[FBCollectionOperations indecesFromArray:@[@(FBSimulatorStateCreating), @(FBSimulatorStateShutdown)]]],
    [FBiOSTargetQuery states:[FBCollectionOperations indecesFromArray:@[@(FBSimulatorStateCreating), @(FBSimulatorStateShutdown)]]],
    [FBiOSTargetQuery udids:@[@"BA1248D3-24B2-43F5-B1CD-57DCB000D12E", @"C5579925-158B-4802-96C3-58B564C901C1", @"41862F9E-A8CA-4816-B4C1-251DA57C1143"]],
  ];
  [self assertEqualityOfCopy:values];
  [self assertUnarchiving:values];
  [self assertJSONSerialization:values];
  [self assertJSONDeserialization:values];
}

@end
