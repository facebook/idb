/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;
@class FBSimulator;
@class FBTestLaunchConfiguration;
@class FBTestManager;
@class FBTestManagerResult;
@protocol FBTestManagerTestReporter;
@protocol FBXCTestPreparationStrategy;

/**
 A Strategy that encompasses a Single Test Run on a Simulator.
 */
@interface FBManagedTestRunStrategy : NSObject

#pragma mark Initializers

/**
 Creates and returns a new Test Run Strategy.

 @param target the Target to use.
 @param configuration the configuration to use.
 @param reporter the reporter to use.
 @param logger the logger to use.
 @param testPreparationStrategy Test preparation strategy to use
 @return a new Test Run Strategy instance.
 */
+ (instancetype)strategyWithTarget:(id<FBiOSTarget>)target configuration:(FBTestLaunchConfiguration *)configuration reporter:(id<FBTestManagerTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger testPreparationStrategy:(id<FBXCTestPreparationStrategy>)testPreparationStrategy;

#pragma mark Public Methods

/**
 Starts the Connection to the Test Host.

 @return A future that resolves with the Test Manager.
 */
- (FBFuture<FBTestManager *> *)connectAndStart;

@end

NS_ASSUME_NONNULL_END
