/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
  target0.name = @"Target0";
  target0.udid = @"AA";
  target0.deviceType = FBiOSTargetConfiguration.nameToDevice[FBDeviceModeliPhone5];
  target0.osVersion = FBiOSTargetConfiguration.nameToOSVersion[FBOSVersionNameiOS_9_0];
  target0.targetType = FBiOSTargetTypeDevice;

  FBiOSTargetDouble *target1 = [FBiOSTargetDouble new];
  target1.name = @"Target1";
  target1.udid = @"BB";
  target1.deviceType = FBiOSTargetConfiguration.nameToDevice[FBDeviceModeliPhone6];
  target1.osVersion = FBiOSTargetConfiguration.nameToOSVersion[FBOSVersionNameiOS_9_1];
  target1.targetType = FBiOSTargetTypeDevice;

  FBiOSTargetDouble *target2 = [FBiOSTargetDouble new];
  target2.name = @"Target2";
  target2.udid = @"CC";
  target2.deviceType = FBiOSTargetConfiguration.nameToDevice[FBDeviceModeliPad2];
  target2.osVersion = FBiOSTargetConfiguration.nameToOSVersion[FBOSVersionNameiOS_9_2];
  target2.targetType = FBiOSTargetTypeDevice;

  FBiOSTargetDouble *target3 = [FBiOSTargetDouble new];
  target3.name = @"Target3";
  target3.udid = @"DD";
  target3.deviceType = FBiOSTargetConfiguration.nameToDevice[FBDeviceModeliPhone5];
  target3.osVersion = FBiOSTargetConfiguration.nameToOSVersion[FBOSVersionNameiOS_9_0];
  target3.targetType = FBiOSTargetTypeSimulator;

  FBiOSTargetDouble *target4 = [FBiOSTargetDouble new];
  target4.name = @"Target4";
  target4.udid = @"EE";
  target4.deviceType = FBiOSTargetConfiguration.nameToDevice[FBDeviceModeliPhone6];
  target4.osVersion = FBiOSTargetConfiguration.nameToOSVersion[FBOSVersionNameiOS_9_1];
  target4.targetType = FBiOSTargetTypeSimulator;

  FBiOSTargetDouble *target5 = [FBiOSTargetDouble new];
  target5.name = @"Target5";
  target5.udid = @"FF";
  target5.deviceType = FBiOSTargetConfiguration.nameToDevice[FBDeviceModeliPad2];
  target5.osVersion = FBiOSTargetConfiguration.nameToOSVersion[FBOSVersionNameiOS_9_2];
  target5.targetType = FBiOSTargetTypeSimulator;

  return @[target0, target1, target2, target3, target4, target5];
}

- (void)testEmptyQuery
{
  NSArray<id<FBiOSTarget>> *targets = self.targets;
  NSArray<id<FBiOSTarget>> *expected = targets;
  NSArray<id<FBiOSTargetInfo>> *actual = [[FBiOSTargetQuery allTargets] filter:targets];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testQueryUDIDs
{
  NSArray<id<FBiOSTarget>> *targets = self.targets;
  NSArray<id<FBiOSTarget>> *expected = @[targets[0], targets[3], targets[4]];
  NSArray<id<FBiOSTargetInfo>> *actual = [[FBiOSTargetQuery udids:@[@"AA", @"DD", @"EE"]] filter:targets];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testQueryDevices
{
  NSArray<id<FBiOSTarget>> *targets = self.targets;
  NSArray<id<FBiOSTarget>> *expected = @[targets[0], targets[1], targets[2]];
  NSArray<id<FBiOSTargetInfo>> *actual = [[FBiOSTargetQuery targetType:FBiOSTargetTypeDevice] filter:targets];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testQuerySimulators
{
  NSArray<id<FBiOSTarget>> *targets = self.targets;
  NSArray<id<FBiOSTarget>> *expected = @[targets[3], targets[4], targets[5]];
  NSArray<id<FBiOSTargetInfo>> *actual = [[FBiOSTargetQuery targetType:FBiOSTargetTypeSimulator] filter:targets];
  XCTAssertEqualObjects(expected, actual);
}

- (void)testNames
{
  NSArray<id<FBiOSTarget>> *targets = self.targets;
  NSArray<id<FBiOSTarget>> *expected = @[targets[0], targets[4]];
  NSArray<id<FBiOSTargetInfo>> *actual = [[FBiOSTargetQuery names:@[@"Target0", @"Target4"]] filter:targets];
  XCTAssertEqualObjects(expected, actual);
}

@end
