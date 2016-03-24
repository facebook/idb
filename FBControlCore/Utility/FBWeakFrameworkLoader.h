/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@protocol FBControlCoreLogger;

/**
 A Utility Class for loading weak-linked Frameworks at runtime.
 */
@interface FBWeakFrameworkLoader : NSObject

/**
 Loads a Mapping of Private Frameworks.
 Will avoid re-loading allready loaded Frameworks.

 @param classMapping a mapping of Class Name to Framework Path. The Framework path is resolved relative to the current Developer Directory.
 @param logger a logger for logging framework loading activities.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
+ (BOOL)loadPrivateFrameworks:(NSDictionary<NSString *, NSString *> *)classMapping logger:(id<FBControlCoreLogger>)logger error:(NSError **)error;

@end
