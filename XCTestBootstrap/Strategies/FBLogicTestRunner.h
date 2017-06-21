/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

NS_ASSUME_NONNULL_BEGIN

@class FBLogicTestConfiguration;
@class FBSimulator;

@protocol FBControlCoreLogger;
@protocol FBXCTestReporter;

/**
 A Runner for Logic Tests
 */
@interface FBLogicTestRunner : NSObject <FBXCTestRunner>

/**
 Creates a Logic Test Runner for iOS with the Provided Parameters.

 @param configuration the Configuration to use.
 @return a new Logic Test Runner.
 */
+ (instancetype)runnerWithStrategy:(id<FBLogicTestStrategy>)strategy configuration:(FBLogicTestConfiguration *)configuration reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
