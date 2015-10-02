/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

/**
 Conveniences for concurent colection operations
 */
@interface FBConcurrentCollectionOperations : NSObject

/**
 Generate an array of objects from indeces. Indeces where nil is returned will contain `NSNull.null`

 @param count the number of generations to execute
 @param block the block to generate objects from.
 */
+ (NSArray *)generate:(NSInteger)count withBlock:( id(^)(NSUInteger index) )block;

/**
 Map an array of objects concurrently.

 @param array the array to map.
 @param block the block to map objects with.
 */
+ (NSArray *)map:(NSArray *)array withBlock:( id(^)(id object) )block;

/**
 Map and then filter an array of objects concurrently.

 @param array the array to map/filter
 @param predicate the predicate to filter the mapped objects with.
 @param block the block to map objects with.
 */
+ (NSArray *)filterMap:(NSArray *)array predicate:(NSPredicate *)predicate map:(id (^)(id))block;

@end
