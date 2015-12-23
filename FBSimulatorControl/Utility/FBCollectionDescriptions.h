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
 Better String representations of Collections.
 */
@interface FBCollectionDescriptions : NSObject

/**
 Creates a One-Line Array description from the array, using the -[NSObject description] keypath.

 @param array the Array to construct a description for.
 */
+ (NSString *)oneLineDescriptionFromArray:(NSArray *)array;

/**
 Creates a One-Line Array description from the array, with a given keyPath.

 @param array the Array to construct a description for.
 @param keyPath the Key Path, to obtain a String description from.
 */
+ (NSString *)oneLineDescriptionFromArray:(NSArray *)array atKeyPath:(NSString *)keyPath;

/**
 Creates a One-Line Array description from the Dictionary.

 @param dictionary the Dictionary to construct a description for.
 */
+ (NSString *)oneLineDescriptionFromDictionary:(NSDictionary *)dictionary;

@end
