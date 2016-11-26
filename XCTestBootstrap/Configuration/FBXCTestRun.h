/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBXCTestRunTarget;

NS_ASSUME_NONNULL_BEGIN

/**
 Reads a .xctestrun file from a given path and provides access to its properties.
 */
@interface FBXCTestRun : NSObject

/**
 The designated initializer

 @param testRunFilePath path to .xctestrun file
 @return a new FBXCTestRun Instance
 */
+ (instancetype)withTestRunFileAtPath:(NSString *)testRunFilePath;

/**
 Array of FBXCTestRunTarget that were loaded from the given .xctestrun file.
 */
@property (nonatomic, copy, readonly) NSArray<FBXCTestRunTarget *> *targets;

/**
 @param error If there is an error, upon return contains an NSError object that describes the problem.
 @return prepared test run configuration if the operation succeeds, otherwise nil.
 */
- (nullable instancetype)buildWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
