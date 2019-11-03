/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBConcurrentCollectionOperations.h"

@interface FBConcurrentCollectionOperations_FilterTerminal : NSObject

+ (instancetype)terminal;

@end

@implementation FBConcurrentCollectionOperations_FilterTerminal

+ (instancetype)terminal
{
  static dispatch_once_t onceToken;
  static FBConcurrentCollectionOperations_FilterTerminal *terminal;
  dispatch_once(&onceToken, ^{
    terminal = [FBConcurrentCollectionOperations_FilterTerminal new];
  });
  return terminal;
}

@end

@implementation FBConcurrentCollectionOperations

#pragma mark Public

+ (NSArray *)generate:(NSUInteger)count withBlock:( id(^)(NSUInteger index) )block
{
  NSMutableArray *array = [NSMutableArray array];
  for (NSUInteger index = 0; index < count; index++) {
    [array addObject:NSNull.null];
  }

  dispatch_apply((size_t) count, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^ (size_t iteration) {
    id object = block(iteration);
    if (object) {
      @synchronized(array) {
        array[iteration] = object;
      }
    }
  });
  return [array copy];
}

+ (NSArray *)map:(NSArray *)array withBlock:( id(^)(id object) )block
{
  return [self
    generate:array.count
    withBlock:^ id (NSUInteger index) {
      return block(array[index]);
    }];
}

+ (NSArray *)filter:(NSArray *)array predicate:(NSPredicate *)predicate
{
  return [self filterMap:array predicate:predicate map:^ id (id object) {
    return object;
  }];
}

+ (NSArray *)mapFilter:(NSArray *)array map:(id (^)(id))block predicate:(NSPredicate *)predicate
{
  NSMutableArray *output = [NSMutableArray array];
  for (NSUInteger index = 0; index < array.count; index++) {
    [output addObject:NSNull.null];
  }

  dispatch_apply(array.count, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^ (size_t iteration) {
    id object = block(array[iteration]);
    BOOL pass = [predicate evaluateWithObject:object];
    if (!pass) {
      object = FBConcurrentCollectionOperations_FilterTerminal.terminal;
    }
    else if (!object) {
      object = NSNull.null;
    }
    @synchronized(output) {
      output[iteration] = object;
    }
  });

  return [output filteredArrayUsingPredicate:self.nonTerminalPredicate];
}

+ (NSArray *)filterMap:(NSArray *)array predicate:(NSPredicate *)predicate map:(id (^)(id))block
{
  return [[self
    map:array
    withBlock:^ id (id object) {
      BOOL pass = [predicate evaluateWithObject:object];
      if (!pass) {
        return FBConcurrentCollectionOperations_FilterTerminal.terminal;
      }
      object = block(object);
      if (!object) {
        return NSNull.null;
      }
      return object;
    }]
    filteredArrayUsingPredicate:self.nonTerminalPredicate];
}

#pragma mark Private

+ (NSPredicate *)nonTerminalPredicate
{
  static dispatch_once_t onceToken;
  static NSPredicate *predicate;
  dispatch_once(&onceToken, ^{
    predicate = [NSPredicate predicateWithBlock:^ BOOL (id evaluatedObject, NSDictionary *_) {
      return evaluatedObject != FBConcurrentCollectionOperations_FilterTerminal.terminal;
    }];
  });
  return predicate;
}

@end
