/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class FBSimulatorProcessFetcher;
@protocol FBControlCoreLogger;

NS_ASSUME_NONNULL_BEGIN

/**
 A Strategy for killing 'com.apple.CoreSimulatorService' processes that are not from the current Xcode version.
 */
@interface FBCoreSimulatorTerminationStrategy : NSObject

#pragma mark Initializers

/**
 Creates and returns a new Core Simulator Termination Strategy from the arguments.

 @param processFetcher the Process Query object to use.
 @param workQueue the work queue to perform work on.
 @param logger the logger to use.
 @return a new Termination Strategy
 */
+ (instancetype)strategyWithProcessFetcher:(FBSimulatorProcessFetcher *)processFetcher workQueue:(dispatch_queue_t)workQueue logger:(id<FBControlCoreLogger>)logger;

#pragma mark Public Methods

/**
 Kills all of the 'com.apple.CoreSimulatorService' processes that are not used by the current `FBSimulatorControl` configuration.
 Running multiple versions of the Service on the same machine can lead to instability such as Simulator statuses not updating.

 @param error an error out if any error occured.
 @return an YES if successful, nil otherwise.
 */
- (BOOL)killSpuriousCoreSimulatorServicesWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
