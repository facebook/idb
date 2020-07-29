/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBCollectionOperations.h"

@implementation FBCollectionOperations

#pragma mark Public

+ (NSArray<NSNumber *> *)arrayFromIndeces:(NSIndexSet *)indeces
{
  NSMutableArray<NSNumber *> *array = [NSMutableArray array];
  [indeces enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *_) {
    [array addObject:@(index)];
  }];
  return [array copy];
}

+ (NSDictionary<NSString *, id> *)recursiveFilteredJSONSerializableRepresentationOfDictionary:(NSDictionary<NSString *, id> *)input
{
  NSMutableDictionary<NSString *, id> *output = NSMutableDictionary.dictionary;
  for (NSString *key in input.allKeys) {
    id value = [self jsonSerializableValueOrNil:input[key]];
    if (!value) {
      continue;
    }
    output[key] = value;
  }
  return output;
}

+ (NSArray<id> *)recursiveFilteredJSONSerializableRepresentationOfArray:(NSArray<id> *)input
{
  NSMutableArray<id> *output = NSMutableArray.array;
  for (id value in input) {
    id resolved = [self jsonSerializableValueOrNil:value];
    if (!resolved) {
      continue;;
    }
    [output addObject:resolved];
  }
  return output;
}

+ (NSIndexSet *)indecesFromArray:(NSArray<NSNumber *> *)array
{
  NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];
  for (NSNumber *number in array) {
    [indexSet addIndex:number.unsignedIntegerValue];
  }
  return [indexSet copy];
}

+ (nullable id)nullableValueForDictionary:(NSDictionary<id<NSCopying>, id> *)dictionary key:(id<NSCopying>)key
{
  id value = dictionary[key];
  if ([value isKindOfClass:NSNull.class]) {
    return nil;
  }
  return value;
}

+ (NSArray *)arrayWithObject:(id)object count:(NSUInteger)count
{
  NSMutableArray *array = [NSMutableArray arrayWithCapacity:count];
  for (NSUInteger index = 0; index < count; index ++) {
    array[index] = object;
  }
  return [array copy];
}

#pragma mark Private

+ (id)jsonSerializableValueOrNil:(id)value
{
  if ([value isKindOfClass:NSString.class]) {
    return value;
  }
  if ([value isKindOfClass:NSNumber.class]) {
    return value;
  }
  if ([value isKindOfClass:NSDictionary.class]) {
    return [self recursiveFilteredJSONSerializableRepresentationOfDictionary:value];
  }
  if ([value isKindOfClass:NSArray.class]) {
    return [self recursiveFilteredJSONSerializableRepresentationOfArray:value];
  }
  return nil;
}

@end
