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

@class FBXCTestConfiguration;
@class FBXCTestContext;

/**
 The base runner for fbxctest.
 */
@interface FBXCTestRunner : NSObject

#pragma mark Initializers

/**
 The Designated Initializer
 
 @param configuration the test configuration.
 @param context the context to run with.
 */
+ (instancetype)testRunnerWithConfiguration:(FBXCTestConfiguration *)configuration context:(FBXCTestContext *)context;

#pragma mark Public Methods

/**
 Executes the Tests.
 
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)executeTestsWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
