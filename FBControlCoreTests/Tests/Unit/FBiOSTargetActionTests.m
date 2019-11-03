/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import "FBControlCoreValueTestCase.h"

@interface FBiOSTargetFutureTests : FBControlCoreValueTestCase

@end

@implementation FBiOSTargetFutureTests

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
