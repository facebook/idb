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
#import <XCTestBootstrap/XCTestBootstrap.h>

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
  [self assertJSONDeserialization:values];
}

@end
