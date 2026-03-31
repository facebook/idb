/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 Conveniences for concurent collection operations.
 The Predicates and Blocks Passed to these functions must work in a thread-safe manner, inspecting immutable values is the way to go.
 */
@interface FBConcurrentCollectionOperations : NSObject

/**
 Generate an array of objects from indices. Indices where nil is returned will contain `NSNull.null`

 @param count the number of generations to execute
 @param block the block to generate objects from.
 @return a Generated Array of Objects.
 */
+ (nonnull NSArray *)generate:(NSUInteger)count withBlock:(nonnull id _Nonnull (^)(NSUInteger index))block;

/**
 Map an array of objects concurrently.

 @param array the array to map.
 @param block the block to map objects with.
 @return a Mapped Array of Objects.
 */
+ (nonnull NSArray *)map:(nonnull NSArray *)array withBlock:(nonnull id _Nonnull (^)(id _Nonnull object))block;

/**
 Filter an array of objects concurrently.

 @param array the array to map/filter.
 @param predicate the predicate to filter the objects with, before they are mapped.
 @return a Filter Array of Objects.
 */
+ (nonnull NSArray *)filter:(nonnull NSArray *)array predicate:(nonnull NSPredicate *)predicate;

/**
 Map and then filter an array of objects concurrently.

 @param array the array to map/filter.
 @param block the block to map objects with.
 @param predicate the predicate to filter the mapped objects with.
 @return a Mapped then Filtered array of objects.
 */
+ (nonnull NSArray *)mapFilter:(nonnull NSArray *)array map:(nonnull id _Nonnull (^)(id _Nonnull))block predicate:(nonnull NSPredicate *)predicate;

/**
 Filter then map an array of objects concurrently.

 @param array the array to map/filter.
 @param predicate the predicate to filter the objects with, before they are mapped.
 @param block the block to map objects with.
 @return a Filtered then Mapped array of objects.
 */
+ (nonnull NSArray *)filterMap:(nonnull NSArray *)array predicate:(nonnull NSPredicate *)predicate map:(nonnull id _Nonnull (^)(id _Nonnull))block;

@end
