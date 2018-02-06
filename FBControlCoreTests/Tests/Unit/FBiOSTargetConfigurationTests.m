/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import "FBControlCoreValueTestCase.h"

@interface FBiOSTargetConfigurationTests : FBControlCoreValueTestCase

@end

@implementation FBiOSTargetConfigurationTests

+ (NSArray<FBDeviceType *> *)deviceTypeConfigurations
{
  return [FBiOSTargetConfiguration.nameToDevice allValues];
}

+ (NSArray<FBOSVersion *> *)osVersionConfigurations
{
  return [FBiOSTargetConfiguration.nameToOSVersion allValues];
}

+ (NSArray<FBiOSTargetScreenInfo *> *)screenConfigurations
{
  return @[
    [[FBiOSTargetScreenInfo alloc] initWithWidthPixels:320 heightPixels:480 scale:1],
    [[FBiOSTargetScreenInfo alloc] initWithWidthPixels:640 heightPixels:960 scale:2],
  ];
}

- (void)testDeviceTypes
{
  NSArray<FBDeviceType *> *configurations = FBiOSTargetConfigurationTests.deviceTypeConfigurations;
  [self assertEqualityOfCopy:configurations];
}

- (void)testOSVersions
{
  NSArray<FBOSVersion *> *configurations = FBiOSTargetConfigurationTests.osVersionConfigurations;
  [self assertEqualityOfCopy:configurations];
}

- (void)testScreenSizes
{
  NSArray<FBiOSTargetScreenInfo *> *configurations = FBiOSTargetConfigurationTests.screenConfigurations;
  [self assertEqualityOfCopy:configurations];
}

@end
