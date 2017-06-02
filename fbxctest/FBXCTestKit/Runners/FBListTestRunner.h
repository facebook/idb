/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBXCTestKit/FBXCTestRunner.h>

NS_ASSUME_NONNULL_BEGIN

@class FBListTestConfiguration;
@class FBXCTestContext;

/**
 A Runner for Listing Tests.
 */
@interface FBListTestRunner : NSObject <FBXCTestRunner>

/**
 Create and return a new Runner for listing tests on macOS.

 @param configuration the the configuration to use.
 @param context the test context to use.
 */
+ (instancetype)macOSRunnerWithConfiguration:(FBListTestConfiguration *)configuration context:(FBXCTestContext *)context;

@end

NS_ASSUME_NONNULL_END
