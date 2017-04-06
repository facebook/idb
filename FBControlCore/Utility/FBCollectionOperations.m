/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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

@end
