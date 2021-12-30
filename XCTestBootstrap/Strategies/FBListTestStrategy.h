/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/FBXCTestRunner.h>

NS_ASSUME_NONNULL_BEGIN

@class FBListTestConfiguration;

@protocol FBXCTestReporter;
@protocol FBProcessSpawnCommands;

/**
 A Runner for Listing Tests.
 */
@interface FBListTestStrategy : NSObject

#pragma mark Initializers

/**
 Create and return a new Runner for listing tests on macOS.

 @param target the target to run against.
 @param configuration the the configuration to use.
 @return a new FBListTestStrategy instance.
 */
- (instancetype)initWithTarget:(id<FBiOSTarget, FBProcessSpawnCommands, FBXCTestExtendedCommands>)target configuration:(FBListTestConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger;

#pragma mark Public Methods

/**
 List the tests in the test bundle.
 */
- (FBFuture<NSArray<NSString *> *> *)listTests;

/**
 Wraps the Strategy in a Reporter.

 @param reporter the reporter to wrap in.
 @return a Test Runner that wraps the underlying strategy.
 */
- (id<FBXCTestRunner>)wrapInReporter:(id<FBXCTestReporter>)reporter;

@end

NS_ASSUME_NONNULL_END
