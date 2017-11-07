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

/**
 A Strategy that encompasses a Single Test Run on a Simulator.
 */
@interface FBSimulatorTestRunStrategy : NSObject

#pragma mark Initializers

/**
 Creates and returns a new Test Run Strategy.

 @param simulator the Simulator to use.
 @param configuration the configuration to use.
 @param reporter the reporter to use.
 @param workingDirectory a directory which can be used for storage of temporary files.
 @return a new Test Run Strategy instance.
 */
+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator configuration:(FBTestLaunchConfiguration *)configuration workingDirectory:(NSString *)workingDirectory reporter:(id<FBTestManagerTestReporter>)reporter;

#pragma mark Public Methods

/**
 Starts the Connection to the Test Host.

 @return A future that resolves with the Test Manager.
 */
- (FBFuture<FBTestManager *> *)connectAndStart;

@end

NS_ASSUME_NONNULL_END
