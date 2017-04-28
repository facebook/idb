/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBLogicTestConfiguration;
@class FBSimulator;
@class FBXCTestContext;

NS_ASSUME_NONNULL_BEGIN

/**
 A Runner for Logic Tests
 */
@interface FBLogicTestRunner : NSObject

/**
 Creates a Logic Test Runner for iOS with the Provided Parameters.

 @param simulator the Simulator to run on.
 @param configuration the Configuration to use.
 @param context the test context
 @return a new Logic Test Runner.
 */
+ (instancetype)iOSRunnerWithSimulator:(FBSimulator *)simulator configuration:(FBLogicTestConfiguration *)configuration context:(FBXCTestContext *)context;

/**
 Creates a Logic Test Runner for macOS with the Provided Parameters.

 @param configuration the Configuration to use.
 @param context the test context
 @return a new Logic Test Runner.
 */
+ (instancetype)macOSRunnerWithConfiguration:(FBLogicTestConfiguration *)configuration context:(FBXCTestContext *)context;

/**
 Run the Logic Tests.

 @param error an error out for any error that occurs.
 @return YES if the test run completed. NO otherwise.
 */
- (BOOL)runTestsWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
