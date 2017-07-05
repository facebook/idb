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

@interface FBControlCoreConfigurationVariantsTests : FBControlCoreValueTestCase

@end

@implementation FBControlCoreConfigurationVariantsTests

+ (NSArray<FBDeviceType *> *)deviceTypeConfigurations
{
  return [FBControlCoreConfigurationVariants.nameToDevice allValues];
}

+ (NSArray<FBOSVersion *> *)osVersionConfigurations
{
  return [FBControlCoreConfigurationVariants.nameToOSVersion allValues];
}

- (void)testDeviceTypes
{
  NSArray<FBDeviceType *> *configurations = FBControlCoreConfigurationVariantsTests.deviceTypeConfigurations;
  [self assertEqualityOfCopy:configurations];
  [self assertUnarchiving:configurations];
}

- (void)testOSVersions
{
  NSArray<FBOSVersion *> *configurations = FBControlCoreConfigurationVariantsTests.osVersionConfigurations;
  [self assertEqualityOfCopy:configurations];
  [self assertUnarchiving:configurations];
}

@end
