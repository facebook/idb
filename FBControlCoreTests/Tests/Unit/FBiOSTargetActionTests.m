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

@interface FBiOSTargetActionTests : FBControlCoreValueTestCase

@end

@implementation FBiOSTargetActionTests

- (void)testValueSemantics
{
  NSArray<id<FBiOSTargetFuture>> *overrides = @[
    [FBApplicationInstallConfiguration applicationInstallWithPath:@"/some.app" codesign:NO],
    [FBApplicationInstallConfiguration applicationInstallWithPath:@"/some.ipa" codesign:YES],
    [FBApplicationInstallConfiguration applicationInstallWithPath:@"/some.app" codesign:YES],
  ];

  [self assertEqualityOfCopy:overrides];
  [self assertJSONSerialization:overrides];
  [self assertJSONDeserialization:overrides];
}

@end
