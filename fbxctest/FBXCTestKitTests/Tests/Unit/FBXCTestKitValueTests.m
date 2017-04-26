/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestKitFixtures.h"

#import <FBControlCore/FBControlCore.h>
#import <FBXCTestKit/FBXCTestKit.h>
#import <XCTest/XCTest.h>

#import "FBControlCoreValueTestCase.h"

@interface FBXCTestKitValueTests : FBControlCoreValueTestCase
@end

@implementation FBXCTestKitValueTests

- (void)testShimConfiguration
{
  NSArray<FBXCTestShimConfiguration *> *values = @[
    [[FBXCTestShimConfiguration alloc] initWithiOSSimulatorTestShim:@"/ios_test.x" macTestShim:@"/mac_test.x" macQueryShim:@"/mac_query.x"],
  ];
  [self assertEqualityOfCopy:values];
  [self assertJSONSerialization:values];
}

- (void)testDestination
{
  NSArray<FBXCTestDestination *> *values = @[
    [[FBXCTestDestinationMacOSX alloc] init],
    [[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:nil version:nil],
    [[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:FBDeviceModeliPhone6 version:FBOSVersionNameiOS_10_0],
    [[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:FBDeviceModeliPhone7 version:nil],
    [[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:nil version:FBOSVersionNameiOS_10_3],
  ];
  [self assertEqualityOfCopy:values];
  [self assertJSONSerialization:values];
  [self assertJSONDeserialization:values];
}

@end
