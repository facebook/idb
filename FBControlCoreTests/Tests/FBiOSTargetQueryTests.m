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
#import "FBiOSTargetDouble.h"

@interface FBiOSTargetQueryTests : FBControlCoreValueTestCase

@end

@implementation FBiOSTargetQueryTests

- (NSArray<id<FBiOSTarget>> *)targets
{
  FBiOSTargetDouble *target0 = [FBiOSTargetDouble new];
  target0.udid = @"AA";
  target0.deviceConfiguration = FBControlCoreConfiguration_Device_iPhone5.new;
  target0.osConfiguration = FBControlCoreConfiguration_iOS_9_0.new;
  target0.targetType = FBiOSTargetTypeDevice;

  FBiOSTargetDouble *target1 = [FBiOSTargetDouble new];
  target1.udid = @"BB";
  target1.deviceConfiguration = FBControlCoreConfiguration_Device_iPhone6.new;
  target1.osConfiguration = FBControlCoreConfiguration_iOS_9_1.new;
  target1.targetType = FBiOSTargetTypeDevice;

  FBiOSTargetDouble *target2 = [FBiOSTargetDouble new];
  target2.udid = @"CC";
  target2.deviceConfiguration = FBControlCoreConfiguration_Device_iPad2.new;
  target2.osConfiguration = FBControlCoreConfiguration_iOS_9_2.new;
  target2.targetType = FBiOSTargetTypeDevice;

  FBiOSTargetDouble *target3 = [FBiOSTargetDouble new];
  target3.udid = @"DD";
  target3.deviceConfiguration = FBControlCoreConfiguration_Device_iPhone5.new;
  target3.osConfiguration = FBControlCoreConfiguration_iOS_9_0.new;
  target3.targetType = FBiOSTargetTypeSimulator;

  FBiOSTargetDouble *target4 = [FBiOSTargetDouble new];
  target4.udid = @"EE";
  target4.deviceConfiguration = FBControlCoreConfiguration_Device_iPhone6.new;
  target4.osConfiguration = FBControlCoreConfiguration_iOS_9_1.new;
  target4.targetType = FBiOSTargetTypeSimulator;

  FBiOSTargetDouble *target5 = [FBiOSTargetDouble new];
  target5.udid = @"FF";
  target5.deviceConfiguration = FBControlCoreConfiguration_Device_iPad2.new;
  target5.osConfiguration = FBControlCoreConfiguration_iOS_9_2.new;
  target5.targetType = FBiOSTargetTypeSimulator;

  return @[target0, target1, target2, target3, target4, target5];
}

- (void)testValueSemantics
{
  NSArray<FBiOSTargetQuery *> *values = @[
    [[[FBiOSTargetQuery udids:@[@"foo", @"bar"]] range:NSMakeRange(2, 10)] devices:@[FBControlCoreConfiguration_Device_iPhone5.new, FBControlCoreConfiguration_Device_iPad2.new]],
    [[FBiOSTargetQuery states:[NSIndexSet indexSetWithIndex:FBSimulatorStateBooting]] osVersions:@[FBOSVersionNameiOS_7_1, FBOSVersionNameiOS_9_0]],
    [[FBiOSTargetQuery udids:@[@"BA1248D3-24B2-43F5-B1CD-57DCB000D12E"]] states:[FBCollectionOperations indecesFromArray:@[@(FBSimulatorStateBooted), @(FBSimulatorStateBooting)]]],
    [FBiOSTargetQuery allTargets],
    [FBiOSTargetQuery targetType:FBiOSTargetTypeDevice],
    [FBiOSTargetQuery targetType:FBiOSTargetTypeSimulator],
    [FBiOSTargetQuery targetType:FBiOSTargetTypeNone],
    [FBiOSTargetQuery devices:@[FBControlCoreConfiguration_Device_iPad2.new, FBControlCoreConfiguration_Device_iPadAir.new]],
    [FBiOSTargetQuery osVersions:@[FBOSVersionNameiOS_9_0, FBOSVersionNameiOS_9_1]],
    [FBiOSTargetQuery states:[FBCollectionOperations indecesFromArray:@[@(FBSimulatorStateCreating), @(FBSimulatorStateShutdown)]]],
    [FBiOSTargetQuery states:[FBCollectionOperations indecesFromArray:@[@(FBSimulatorStateCreating), @(FBSimulatorStateShutdown)]]],
    [FBiOSTargetQuery udids:@[@"BA1248D3-24B2-43F5-B1CD-57DCB000D12E", @"C5579925-158B-4802-96C3-58B564C901C1", @"41862F9E-A8CA-4816-B4C1-251DA57C1143"]],
  ];

  [self assertEqualityOfCopy:values];
  [self assertUnarchiving:values];
  [self assertJSONSerialization:values];
  [self assertJSONDeserialization:values];
}

- (void)testEmptyQuery
{
  NSArray<id<FBiOSTarget>> *targets = self.targets;
  NSArray<id<FBiOSTarget>> *expected = targets;
  NSArray<id<FBiOSTarget>> *actual = [[FBiOSTargetQuery allTargets] filter:targets];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testQueryUDIDs
{
  NSArray<id<FBiOSTarget>> *targets = self.targets;
  NSArray<id<FBiOSTarget>> *expected = @[targets[0], targets[3], targets[4]];
  NSArray<id<FBiOSTarget>> *actual = [[FBiOSTargetQuery udids:@[@"AA", @"DD", @"EE"]] filter:targets];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testQueryDevices
{
  NSArray<id<FBiOSTarget>> *targets = self.targets;
  NSArray<id<FBiOSTarget>> *expected = @[targets[0], targets[1], targets[2]];
  NSArray<id<FBiOSTarget>> *actual = [[FBiOSTargetQuery targetType:FBiOSTargetTypeDevice] filter:targets];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testQuerySimulators
{
  NSArray<id<FBiOSTarget>> *targets = self.targets;
  NSArray<id<FBiOSTarget>> *expected = @[targets[3], targets[4], targets[5]];
  NSArray<id<FBiOSTarget>> *actual = [[FBiOSTargetQuery targetType:FBiOSTargetTypeSimulator] filter:targets];
  XCTAssertEqualObjects(expected, actual);
}

@end
