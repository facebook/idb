/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
    FBDeviceModeliPhone5c,
    FBDeviceModeliPhone5s,
    FBDeviceModeliPhone6,
    FBDeviceModeliPhone6Plus,
    FBDeviceModeliPhone6S,
    FBDeviceModeliPhone6SPlus,
    FBDeviceModeliPhone7,
    FBDeviceModeliPhone7Plus,
    FBDeviceModeliPhoneSE_1stGeneration,
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
    [deviceTypes addObject:FBiOSTargetConfiguration.nameToDevice[model]];
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
  first.state = FBiOSTargetStateBooted;
  first.deviceType = FBiOSTargetConfiguration.nameToDevice[FBDeviceModeliPhone6S];
  first.osVersion = FBiOSTargetConfiguration.nameToOSVersion[FBOSVersionNameiOS_10_0];

  FBiOSTargetDouble *second = [FBiOSTargetDouble new];
  second.targetType = FBiOSTargetTypeSimulator;
  first.state = FBiOSTargetStateBooted;
  second.deviceType = FBiOSTargetConfiguration.nameToDevice[FBDeviceModeliPhone6S];
  second.osVersion = FBiOSTargetConfiguration.nameToOSVersion[FBOSVersionNameiOS_10_0];

  XCTAssertEqual(FBiOSTargetComparison(first, second), NSOrderedDescending);
}

- (void)testOSVersionOrdering
{
  FBiOSTargetDouble *first = [FBiOSTargetDouble new];
  first.targetType = FBiOSTargetTypeDevice;
  first.state = FBiOSTargetStateBooted;
  first.deviceType = FBiOSTargetConfiguration.nameToDevice[FBDeviceModeliPhone6S];
  first.osVersion = FBiOSTargetConfiguration.nameToOSVersion[FBOSVersionNameiOS_10_0];

  FBiOSTargetDouble *second = [FBiOSTargetDouble new];
  second.targetType = FBiOSTargetTypeDevice;
  second.deviceType = FBiOSTargetConfiguration.nameToDevice[FBDeviceModeliPhone6S];
  second.osVersion = FBiOSTargetConfiguration.nameToOSVersion[FBOSVersionNameiOS_10_1];

  XCTAssertEqual(FBiOSTargetComparison(first, second), NSOrderedAscending);
}

- (void)testStateOrdering
{
  NSArray<NSNumber *> *stateOrder = @[
    @(FBiOSTargetStateCreating),
    @(FBiOSTargetStateShutdown),
    @(FBiOSTargetStateBooting),
    @(FBiOSTargetStateBooted),
    @(FBiOSTargetStateShuttingDown),
    @(FBiOSTargetStateUnknown),
  ];
  NSMutableArray<id<FBiOSTarget>> *input = [NSMutableArray array];
  for (NSNumber *stateNumber in stateOrder) {
    FBiOSTargetDouble *target = [FBiOSTargetDouble new];
    target.targetType = FBiOSTargetTypeDevice;
    target.state = stateNumber.unsignedIntegerValue;
    target.deviceType = FBiOSTargetConfiguration.nameToDevice[FBDeviceModeliPhone6S];
    target.osVersion = FBiOSTargetConfiguration.nameToOSVersion[FBOSVersionNameiOS_10_0];
    [input addObject:target];
  }
  for (NSUInteger index = 0; index < input.count; index++) {
    FBiOSTargetState expected = stateOrder[index].unsignedIntegerValue;
    FBiOSTargetState actual = input[index].state;
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
    target.state = FBiOSTargetStateBooted;
    target.deviceType = deviceType;
    target.osVersion = FBiOSTargetConfiguration.nameToOSVersion[FBOSVersionNameiOS_10_0];
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
