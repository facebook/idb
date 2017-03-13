/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBSimulator;
@class FBSimulator;
@class FBTestLaunchConfiguration;
@class FBTestManager;
@class FBTestManagerResult;
@protocol FBTestManagerTestReporter;

NS_ASSUME_NONNULL_BEGIN

/**
 A Strategy that encompasses a Single Test Run on a Simulator.
 */
@interface FBSimulatorTestRunStrategy : NSObject

/**
 Creates and returns a new Test Run Strategy.

@param simulator the Simulator to use.
 @param configuration the configuration to use.
 @param reporter the reporter to use.
 @param workingDirectory a directory which can be used for storage of temporary files.
 @return a new Test Run Strategy instance.
 */
+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator configuration:(FBTestLaunchConfiguration *)configuration workingDirectory:(NSString *)workingDirectory reporter:(id<FBTestManagerTestReporter>)reporter;

/**
 Starts the Connection to the Test Host.

 @param error an error out for any error that occurs.
 @return the Test Manager that has connected if successful, nil otherwise.
 */
- (nullable FBTestManager *)connectAndStartWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
