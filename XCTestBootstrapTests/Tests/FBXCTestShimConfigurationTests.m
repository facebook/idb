/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBControlCoreValueTestCase.h"

@interface FBXCTestKitValueTests : FBControlCoreValueTestCase
@end

@implementation FBXCTestKitValueTests

- (void)testShimConfiguration
{
  NSArray<FBXCTestShimConfiguration *> *values = @[
    [[FBXCTestShimConfiguration alloc] initWithiOSSimulatorTestShimPath:@"/ios_test.x" macOSTestShimPath:@"/mac_test.x" macOSQueryShimPath:@"/mac_query.x"],
  ];
  [self assertEqualityOfCopy:values];
  [self assertJSONSerialization:values];
  [self assertJSONDeserialization:values];
}

@end
