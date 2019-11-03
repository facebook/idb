/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

@class FBXCTestConfiguration;

/**
 A Template for Tests that Provide Value-Like Objects.
 */
@interface FBControlCoreValueTestCase : XCTestCase

/**
 Asserts that values are equal when copied.
 */
- (void)assertEqualityOfCopy:(NSArray<NSObject *> *)values;

/**
 Asserts that values can be JSON Serialized
 */
- (void)assertJSONSerialization:(NSArray<id<FBJSONSerializable>> *)values;

/**
 Asserts that values can be serialized and deserialized via json.
 */
- (void)assertJSONDeserialization:(NSArray<id<FBJSONDeserializable>> *)values;

/**
 Asserts that configuration has correct semantics
 */
- (void)assertValueSemanticsOfConfiguration:(id<NSObject, FBJSONSerializable, FBJSONDeserializable, NSCopying>)configuration;

@end
