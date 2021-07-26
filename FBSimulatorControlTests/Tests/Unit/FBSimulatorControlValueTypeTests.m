/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <FBSimulatorControl/FBSimulatorControl.h>
#import <Carbon/Carbon.h>

#import "FBSimulatorControlTestCase.h"
#import "FBSimulatorControlFixtures.h"
#import "FBControlCoreValueTestCase.h"

@interface FBSimulatorControlValueTypeTests : FBControlCoreValueTestCase

@end

@implementation FBSimulatorControlValueTypeTests

- (void)testLaunchConfigurations
{
  NSArray<FBSimulatorBootConfiguration *> *values = @[
    [[FBSimulatorBootConfiguration.defaultConfiguration
      withOptions:FBSimulatorBootOptionsEnableDirectLaunch]
      withScale:FBScale75],
    [[FBSimulatorBootConfiguration.defaultConfiguration
      withBootEnvironment:@{@"FOO": @"BAR"}]
      withScale:FBScale25]
  ];
  [self assertEqualityOfCopy:values];
}

- (void)testLaunchConfigurationScaleAppliedToFramebufferConfiguration
{
  FBSimulatorBootConfiguration *launchConfiguration = [[FBSimulatorBootConfiguration
    defaultConfiguration]
    withOptions:FBSimulatorBootOptionsEnableDirectLaunch];
  XCTAssertNil(launchConfiguration.scale);
  XCTAssertNil(launchConfiguration.scale);

  launchConfiguration = [launchConfiguration withScale:FBScale75];
  XCTAssertEqualObjects(launchConfiguration.scale, FBScale75);
  XCTAssertNotEqualObjects(launchConfiguration.scale, FBScale50);
}

- (void)testHIDEvents
{
  NSArray<FBSimulatorHIDEvent *> *values = @[
    [FBSimulatorHIDEvent tapAtX:10 y:20],
    [FBSimulatorHIDEvent shortButtonPress:FBSimulatorHIDButtonApplePay],
    [FBSimulatorHIDEvent shortButtonPress:FBSimulatorHIDButtonHomeButton],
    [FBSimulatorHIDEvent shortButtonPress:FBSimulatorHIDButtonLock],
    [FBSimulatorHIDEvent shortButtonPress:FBSimulatorHIDButtonSideButton],
    [FBSimulatorHIDEvent shortButtonPress:FBSimulatorHIDButtonSiri],
    [FBSimulatorHIDEvent shortButtonPress:FBSimulatorHIDButtonHomeButton],
    [FBSimulatorHIDEvent shortKeyPress:kVK_ANSI_W],
    [FBSimulatorHIDEvent shortKeyPress:kVK_ANSI_A],
    [FBSimulatorHIDEvent shortKeyPress:kVK_ANSI_R],
    [FBSimulatorHIDEvent shortKeyPress:kVK_ANSI_I],
    [FBSimulatorHIDEvent shortKeyPress:kVK_ANSI_O],
  ];
  [self assertEqualityOfCopy:values];
}

@end
