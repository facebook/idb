/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

 @param indices the indices to extract numbers from.
 @return an Array of Numbers of the indices in the index set.
 */
+ (NSArray<NSNumber *> *)arrayFromIndices:(NSIndexSet *)indices;

/**
 Returns a recursive copy of the dictionary, filtering out any elements that are not JSON-Serializable. Values that are acceptable are:
 - NSString
 - NSNumber
 - NSNull
 - NSArray (filtering out all non-serializable elements)
 - NSDicitionary (filtering out all non-serializable elements)

 @param input the input dictionary.
 @return a filtered dictionary.
 */
+ (NSDictionary<NSString *, id> *)recursiveFilteredJSONSerializableRepresentationOfDictionary:(NSDictionary<NSString *, id> *)input;

/**
 Returns a recursive copy of the array, filtering out any elements that are not JSON-Serializable. Values that are acceptable are:
 - NSString
 - NSNumber
 - NSNull
 - NSArray (filtering out all non-serializable elements)
 - NSDicitionary (filtering out all non-serializable elements)

 @param input the input array.
 @return a filtered array.
 */
+ (NSArray<id> *)recursiveFilteredJSONSerializableRepresentationOfArray:(NSArray<id> *)input;

/**
 Creates and returns an Index Set from an Array of Numbers
 Index Sets can be used for storing a collection of Integers, as can Arrays of Numbers.

 @param array an array of numbers to extract values from
 @return an Index Set of the values in the array.
 */
+ (NSIndexSet *)indicesFromArray:(NSArray<NSNumber *> *)array;

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
