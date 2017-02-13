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

@protocol FBControlCoreLogger;

/**
 Represents a dylib that FBControlCore is dependent on
 */
@interface FBDependentDylib : NSObject

/**
 Creates and returns FBDependentDylib with the given path.

 @param relativePath a path relative to /path/to/Xcode.app/Contents
 @return an FBDependentDylib instance
 */
+ (instancetype)dependentWithRelativePath:(NSString *)relativePath;


/**
 Loads the framework using dlopen.

 @param logger a logger for logging framework loading activities.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)loadWithLogger:(id<FBControlCoreLogger>)logger error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
