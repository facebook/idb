/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBControlCoreValueTestCase.h"

@implementation FBControlCoreValueTestCase

- (void)assertEqualityOfCopy:(NSArray *)values
{
  for (id value in values) {
    id valueCopy = [value copy];
    id valueCopyCopy = [valueCopy copy];
    XCTAssertEqualObjects(value, valueCopy);
    XCTAssertEqualObjects(value, valueCopyCopy);
    XCTAssertEqualObjects(valueCopy, valueCopyCopy);
  }
}

- (void)assertUnarchiving:(NSArray *)values
{
  for (id value in values) {
    NSData *valueData = [NSKeyedArchiver archivedDataWithRootObject:value];
    id valueUnarchived = [NSKeyedUnarchiver unarchiveObjectWithData:valueData];
    XCTAssertEqualObjects(value, valueUnarchived);
  }
}

- (void)assertJSONSerialization:(NSArray *)values
{
  for (id value in values) {
    [self assertStringKeysJSONValues:[value jsonSerializableRepresentation]];
  }
}

- (void)assertJSONDeserialization:(NSArray *)values
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

@end
