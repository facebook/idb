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

@class FBApplicationTestConfiguration;
@class FBSimulator;
@class FBXCTestContext;

/**
 A Runner for Application Tests.
 */
@interface FBApplicationTestRunner : NSObject <FBXCTestRunner>

/**
 Create and return a new Runner for Application Tests on iOS.

 @param simulator the Simulator to use for hosting the Application.
 @param configuration the the configuration to use.
 @param context the test context.
 */
+ (instancetype)iOSRunnerWithSimulator:(FBSimulator *)simulator configuration:(FBApplicationTestConfiguration *)configuration context:(FBXCTestContext *)context;

@end

NS_ASSUME_NONNULL_END
