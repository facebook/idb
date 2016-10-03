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

/**
 A Template for Tests that Provide Value-Like Objects.
 */
@interface FBControlCoreValueTestCase : XCTestCase

/**
 Asserts that values are equal when copied.
 */
- (void)assertEqualityOfCopy:(NSArray<NSObject *> *)values;

/**
 Asserts that values archive and unarchive to the same value.
 */
- (void)assertUnarchiving:(NSArray<id<NSCoding>> *)values;

/**
 Asserts that values can be JSON Serialized
 */
- (void)assertJSONSerialization:(NSArray<id<FBJSONSerializable>> *)values;

/**
 Asserts that values can be serialized and deserialized via json.
 */
- (void)assertJSONDeserialization:(NSArray<id<FBJSONDeserializable>> *)values;

@end
