/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

/**
 A Template for Tests that Provide Value-Like Objects.
 */
@interface FBControlCoreValueTestCase : XCTestCase

/**
 Asserts that values are equal when copied.
 */
- (void)assertEqualityOfCopy:(NSArray<NSObject *> *)values;

@end
