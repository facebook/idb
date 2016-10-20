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

/**
 A Runner for Listing Tests.
 */
@interface FBListTestRunner : NSObject

/**
 Create and return a new Runner for Application Tests.

 @param configuration the the configuration to use.
 */
+ (instancetype)runnerWithConfiguration:(FBXCTestConfiguration *)configuration;

/**
 Lists the tests to the reporter.

 @param error an error out for any error that occurs.
 @return YES if successful, NO othwerwise.
 */
- (BOOL)listTestsWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
