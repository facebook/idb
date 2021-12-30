/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBControlCoreValueTestCase.h"

@implementation FBControlCoreValueTestCase

- (void)assertEqualityOfCopy:(NSArray<NSObject *> *)values
{
  for (id value in values) {
    id valueCopy = [value copy];
    id valueCopyCopy = [valueCopy copy];
    XCTAssertEqualObjects(value, valueCopy);
    XCTAssertEqualObjects(value, valueCopyCopy);
    XCTAssertEqualObjects(valueCopy, valueCopyCopy);
  }
}

@end
