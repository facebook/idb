/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBApplicationTestConfiguration;
@class FBSimulator;

/**
 A Runner for Application Tests.
 */
@interface FBApplicationTestRunner : NSObject

/**
 Create and return a new Runner for Application Tests.

 @param simulator the Simulator to use for hosting the Application.
 @param configuration the the configuration to use.
 */
+ (instancetype)withSimulator:(FBSimulator *)simulator configuration:(FBApplicationTestConfiguration *)configuration;

/**
 Run the Application Tests.

 @param error an error out for any error that occurs.
 @return YES if the test run completed. NO otherwise.
 */
- (BOOL)runTestsWithError:(NSError **)error;

@end
