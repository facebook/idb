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

@end
