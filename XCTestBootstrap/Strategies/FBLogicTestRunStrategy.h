/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

NS_ASSUME_NONNULL_BEGIN

@class FBLogicTestConfiguration;

@protocol FBControlCoreLogger;
@protocol FBLogicXCTestReporter;

/**
 A Runner for Logic Tests
 */
@interface FBLogicTestRunStrategy : NSObject <FBXCTestRunner>

/**
 Creates a Logic Test Runner for iOS with the Provided Parameters.

 @param executor the executor.
 @param configuration the Configuration to use.
 @param reporter the reporter to report to.
 @param logger the logger to use.
 @return a new Logic Test Strategy.
 */
+ (instancetype)strategyWithExecutor:(id<FBXCTestProcessExecutor>)executor configuration:(FBLogicTestConfiguration *)configuration reporter:(id<FBLogicXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
