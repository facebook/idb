/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBCollectionOperations.h"

@implementation FBCollectionOperations

+ (NSArray<NSNumber *> *)arrayFromIndeces:(NSIndexSet *)indeces
{
  NSMutableArray<NSNumber *> *array = [NSMutableArray array];
  [indeces enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *_) {
    [array addObject:@(index)];
  }];
  return [array copy];
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

@end
