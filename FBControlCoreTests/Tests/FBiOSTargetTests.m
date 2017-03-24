/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <XCTest/XCTest.h>

#import "FBiOSTargetDouble.h"

@interface FBiOSTargetTests : XCTestCase

@end

@implementation FBiOSTargetTests

+ (NSArray<FBDeviceModel> *)iPhoneModels
{
  return @[
    FBDeviceModeliPhone4s,
    FBDeviceModeliPhone5,
    FBDeviceModeliPhone5s,
    FBDeviceModeliPhone6,
    FBDeviceModeliPhone6Plus,
    FBDeviceModeliPhone6S,
    FBDeviceModeliPhone6SPlus,
    FBDeviceModeliPhone7,
    FBDeviceModeliPhone7Plus,
    FBDeviceModeliPhoneSE,
  ];
}

+ (NSArray<FBDeviceModel> *)iPadModels
{
  return @[
     FBDeviceModeliPad2,
     FBDeviceModeliPadAir,
     FBDeviceModeliPadAir2,
     FBDeviceModeliPadPro,
     FBDeviceModeliPadPro_12_9_Inch,
     FBDeviceModeliPadPro_9_7_Inch,
     FBDeviceModeliPadRetina,
  ];
}

+ (NSArray<FBDeviceType *> *)deviceTypesForModels:(NSArray<FBDeviceModel> *)models
{
  NSMutableArray<FBDeviceType *> *deviceTypes = [NSMutableArray array];
  for (FBDeviceModel model in models) {
    [deviceTypes addObject:FBControlCoreConfigurationVariants.nameToDevice[model]];
  }
  return [deviceTypes copy];
}

+ (NSArray<FBDeviceType *> *)iPhoneDeviceTypes
{
  return [self deviceTypesForModels:self.iPhoneModels];
}

+ (NSArray<FBDeviceType *> *)iPadDeviceTypes
{
  return [self deviceTypesForModels:self.iPadModels];
}

- (void)testDevicesOrderedFirst
{
  FBiOSTargetDouble *first = [FBiOSTargetDouble new];
  first.targetType = FBiOSTargetTypeDevice;
  first.state = FBSimulatorStateBooted;
  first.deviceType = FBControlCoreConfigurationVariants.nameToDevice[FBDeviceModeliPhone6S];
  first.osVersion = FBControlCoreConfigurationVariants.nameToOSVersion[FBOSVersionNameiOS_10_0];

  FBiOSTargetDouble *second = [FBiOSTargetDouble new];
  second.targetType = FBiOSTargetTypeSimulator;
  first.state = FBSimulatorStateBooted;
  second.deviceType = FBControlCoreConfigurationVariants.nameToDevice[FBDeviceModeliPhone6S];
  second.osVersion = FBControlCoreConfigurationVariants.nameToOSVersion[FBOSVersionNameiOS_10_0];

  XCTAssertEqual(FBiOSTargetComparison(first, second), NSOrderedDescending);
}

- (void)testOSVersionOrdering
{
  FBiOSTargetDouble *first = [FBiOSTargetDouble new];
  first.targetType = FBiOSTargetTypeDevice;
  first.state = FBSimulatorStateBooted;
  first.deviceType = FBControlCoreConfigurationVariants.nameToDevice[FBDeviceModeliPhone6S];
  first.osVersion = FBControlCoreConfigurationVariants.nameToOSVersion[FBOSVersionNameiOS_10_0];

  FBiOSTargetDouble *second = [FBiOSTargetDouble new];
  second.targetType = FBiOSTargetTypeDevice;
  second.deviceType = FBControlCoreConfigurationVariants.nameToDevice[FBDeviceModeliPhone6S];
  second.osVersion = FBControlCoreConfigurationVariants.nameToOSVersion[FBOSVersionNameiOS_10_1];

  XCTAssertEqual(FBiOSTargetComparison(first, second), NSOrderedAscending);
}

- (void)testStateOrdering
{
  NSArray<NSNumber *> *stateOrder = @[
    @(FBSimulatorStateCreating),
    @(FBSimulatorStateShutdown),
    @(FBSimulatorStateBooting),
    @(FBSimulatorStateBooted),
    @(FBSimulatorStateShuttingDown),
    @(FBSimulatorStateUnknown),
  ];
  NSMutableArray<id<FBiOSTarget>> *input = [NSMutableArray array];
  for (NSNumber *stateNumber in stateOrder) {
    FBiOSTargetDouble *target = [FBiOSTargetDouble new];
    target.targetType = FBiOSTargetTypeDevice;
    target.state = stateNumber.unsignedIntegerValue;
    target.deviceType = FBControlCoreConfigurationVariants.nameToDevice[FBDeviceModeliPhone6S];
    target.osVersion = FBControlCoreConfigurationVariants.nameToOSVersion[FBOSVersionNameiOS_10_0];
    [input addObject:target];
  }
  for (NSUInteger index = 0; index < input.count; index++) {
    FBSimulatorState expected = stateOrder[index].unsignedIntegerValue;
    FBSimulatorState actual = input[index].state;
    XCTAssertEqual(expected, actual);
  }
}

- (void)testiPadComesBeforeiPhone
{
  NSArray<FBDeviceType *> *deviceTypes = [FBiOSTargetTests.iPhoneDeviceTypes arrayByAddingObjectsFromArray:FBiOSTargetTests.iPadDeviceTypes];
  NSMutableArray<id<FBiOSTarget>> *input = [NSMutableArray array];
  for (FBDeviceType *deviceType in deviceTypes) {
    FBiOSTargetDouble *target = [FBiOSTargetDouble new];
    target.targetType = FBiOSTargetTypeDevice;
    target.state = FBSimulatorStateBooted;
    target.deviceType = deviceType;
    target.osVersion = FBControlCoreConfigurationVariants.nameToOSVersion[FBOSVersionNameiOS_10_0];
    [input addObject:target];
  }
  NSArray<id<FBiOSTarget>> *output = [[input copy] sortedArrayUsingSelector:@selector(compare:)];
  XCTAssertEqual(input.count, output.count);
  for (NSUInteger index = 0; index < input.count; index++) {
    FBDeviceType *expected = input[index].deviceType;
    FBDeviceType *actual = output[index].deviceType;
    XCTAssertEqualObjects(expected, actual);
  }
}

@end
