/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 Helpers for information about of Collections.
 */
@interface FBCollectionInformation : NSObject

/**
 Creates a One-Line Array description from the array, using the -[NSObject description] keypath.

 @param array the Array to construct a description for.
 */
+ (nonnull NSString *)oneLineDescriptionFromArray:(nonnull NSArray *)array;

/**
 Creates a One-Line Array description from the array, with a given keyPath.

 @param array the Array to construct a description for.
 @param keyPath the Key Path, to obtain a String description from.
 */
+ (nonnull NSString *)oneLineDescriptionFromArray:(nonnull NSArray *)array atKeyPath:(nonnull NSString *)keyPath;

/**
 Creates a One-Line Array description from the Dictionary.

 @param dictionary the Dictionary to construct a description for.
 */
+ (nonnull NSString *)oneLineDescriptionFromDictionary:(nonnull NSDictionary *)dictionary;

/**
 Confirms that the array is homogeneous, with all elements being of a given class.

 @param array the array to check.
 @param cls the class that all elements in the array should belong to.
 @return YES if homogeneous, NO otherwise.
 */
+ (BOOL)isArrayHeterogeneous:(nonnull NSArray *)array withClass:(nonnull Class)cls;

/**
 Confirms that the dictionary is homogeneous, with all keys and values being of the given classes.

 @param dictionary the dictionary to check
 @param keyCls the class that all keys in the dictionary should belong to.
 @param valueCls the class that all values in the dictionary should be belong to.
 @return YES if homogeneous, NO otherwise.
 */
+ (BOOL)isDictionaryHeterogeneous:(nonnull NSDictionary *)dictionary keyClass:(nonnull Class)keyCls valueClass:(nonnull Class)valueCls;

@end
