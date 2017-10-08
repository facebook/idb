/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Conveniences for working with collections.
 */
@interface FBCollectionOperations : NSObject

/**
 Creates and returns an Array of Numbers from an index set.
 Index Sets can be used for storing a collection of Integers, as can Arrays of Numbers.

 @param indeces the indeces to extract numbers from.
 @return an Array of Numbers of the indeces in the index set.
 */
+ (NSArray<NSNumber *> *)arrayFromIndeces:(NSIndexSet *)indeces;

/**
 Creates and returns an Index Set from an Array of Numbers
 Index Sets can be used for storing a collection of Integers, as can Arrays of Numbers.

 @param array an array of numbers to extract values from
 @return an Index Set of the values in the array.
 */
+ (NSIndexSet *)indecesFromArray:(NSArray<NSNumber *> *)array;

/**
 objectForKey, converting NSNull to nil.

 @param dictionary the dictionary to fetch from.
 @param key the key to obtain for.
 @return the value if present, else nil if NSNull.null or not present.
 */
+ (nullable id)nullableValueForDictionary:(NSDictionary<id<NSCopying>, id> *)dictionary key:(id<NSCopying>)key;

/**
 Create an Array of the same object.

 @param object the object.
 @param count the number of occurrences.
 */
+ (NSArray *)arrayWithObject:(id)object count:(NSUInteger)count;

@end

NS_ASSUME_NONNULL_END
