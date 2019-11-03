/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>
#import <FBXCTestKit/FBXCTestKit.h>

#import "FBControlCoreValueTestCase.h"

@interface FBXCTestDestinationTests : FBControlCoreValueTestCase
@end

@implementation FBXCTestDestinationTests

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
