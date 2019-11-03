/*
 * Copyright (c) Facebook, Inc. and its affiliates.
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

- (void)assertJSONSerialization:(NSArray<id<FBJSONSerializable>> *)values
{
  for (id value in values) {
    id json = [value jsonSerializableRepresentation];
    if ([json isKindOfClass:NSDictionary.class]) {
      [self assertStringKeysJSONValues:json];
      return;
    } else if ([json isKindOfClass:NSArray.class]) {
      [self assertJSONValues:json];
      return;
    }
    XCTFail(@"%@ is not a container", json);
  }
}

- (void)assertJSONDeserialization:(NSArray<id<FBJSONDeserializable>> *)values
{
  for (id value in values) {
    id json = [value jsonSerializableRepresentation];
    NSError *error = nil;
    id serializedValue = [[value class] inflateFromJSON:json error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(value, serializedValue);
    XCTAssertEqualObjects(json, [serializedValue jsonSerializableRepresentation]);
  }
}

- (void)assertStringKeysJSONValues:(NSDictionary *)json
{
  NSSet *keyTypes = [NSSet setWithArray:[json.allKeys valueForKey:@"class"]];
  for (Class class in keyTypes) {
    XCTAssertTrue([class isSubclassOfClass:NSString.class]);
  }
  [self assertJSONValues:json.allValues];
}

- (void)assertJSONValues:(NSArray *)json
{
  for (id value in json) {
    if ([value isKindOfClass:NSString.class]) {
      continue;
    }
    if ([value isKindOfClass:NSNumber.class]) {
      continue;
    }
    if ([value isEqual:NSNull.null]) {
      continue;
    }
    if ([value isKindOfClass:NSArray.class]) {
      [self assertJSONValues:value];
      continue;
    }
    if ([value isKindOfClass:NSDictionary.class]) {
      [self assertStringKeysJSONValues:value];
      continue;
    }
    XCTFail(@"%@ is not json encodable", value);
  }
}

- (void)assertValueSemanticsOfConfiguration:(id<NSObject, FBJSONSerializable, FBJSONDeserializable, NSCopying>)configuration
{
  [self assertEqualityOfCopy:@[configuration]];
  [self assertJSONSerialization:@[configuration]];
  [self assertJSONDeserialization:@[configuration]];
}

@end
