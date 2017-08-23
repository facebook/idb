/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <XCTestBootstrap/FBXCTestRunner.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBXCTestReporter;
@protocol FBXCTestProcessExecutor;
@protocol FBControlCoreLogger;

@class FBListTestConfiguration;
@class FBXCTestContext;

/**
 A Runner for Listing Tests.
 */
@interface FBListTestStrategy : NSObject <FBXCTestRunner>

/**
 Create and return a new Runner for listing tests on macOS.

 @param executor the Process Executor.
 @param configuration the the configuration to use.
 @param reporter the reporter to use.
 @param logger the logger to use.
 @return a new FBListTestStrategy instance.
 */
+ (instancetype)strategyWithExecutor:(id<FBXCTestProcessExecutor>)executor configuration:(FBListTestConfiguration *)configuration reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
