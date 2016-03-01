/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBCapacityQueue.h"

@interface FBCapacityQueue ()

@property (nonatomic, strong, readonly) NSMutableArray *array;
@property (nonatomic, assign, readonly) NSUInteger capacity;

@end

@implementation FBCapacityQueue

#pragma mark Initializers

+ (instancetype)withCapacity:(NSUInteger)capacity
{
  return [[self alloc] initWithCapacity:capacity];
}

- (instancetype)initWithCapacity:(NSUInteger)capacity
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _array = [NSMutableArray array];
  _capacity = capacity;

  return self;
}

#pragma mark Public

- (id)push:(id)item
{
  if (self.array.count < self.capacity) {
    [self.array addObject:item];
    return nil;
  }

  id evicted = [self.array firstObject];
  [self.array removeObjectAtIndex:0];
  [self.array addObject:item];
  return evicted;
}

- (id)pop
{
  if (self.array.count == 0) {
    return nil;
  }
  id item = [self.array firstObject];
  [self.array removeObjectAtIndex:0];
  return item;
}

- (NSArray *)popAll
{
  NSArray *all = self.array.copy;
  [self.array removeAllObjects];
  return all;
}

- (NSUInteger)count
{
  return self.array.count;
}

@end
