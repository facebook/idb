/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBControlCoreLogger;
@class FBProcessFetcher;
@class FBProcessInfo;

/**
 An Option Set for Process Termination.
 */
typedef NS_ENUM(NSUInteger, FBProcessTerminationStrategyOptions) {
  FBProcessTerminationStrategyOptionsCheckProcessExistsBeforeSignal = 1 << 2, /** Checks for the process to exist before signalling **/
  FBProcessTerminationStrategyOptionsCheckDeathAfterSignal = 1 << 3, /** Waits for the process to die before returning **/
  FBProcessTerminationStrategyOptionsBackoffToSIGKILL = 1 << 4, /** Whether to backoff to SIGKILL if a less severe signal fails **/
};

/**
 A Configuration for the Strategy.
 */
typedef struct {
  int signo;
  FBProcessTerminationStrategyOptions options;
} FBProcessTerminationStrategyConfiguration;


/**
 A Strategy that defines how to terminate Processes.
 */
@interface FBProcessTerminationStrategy : NSObject

#pragma mark Initializers

/**
 Creates and returns a strategy for the given configuration.

 @param configuration the configuration to use in the strategy.
 @param processFetcher the Process Fetcher to use.
 @param workQueue the queue to perform work on.
 @param logger the logger to use.
 @return a new Process Termination Strategy instance.
 */
+ (instancetype)strategyWithConfiguration:(FBProcessTerminationStrategyConfiguration)configuration processFetcher:(FBProcessFetcher *)processFetcher workQueue:(dispatch_queue_t)workQueue logger:(id<FBControlCoreLogger>)logger;

/**
 Creates and returns a Strategy strategyWith the default configuration.

 @param processFetcher the Process Fetcher to use.
 @param workQueue the queue to perform work on.
 @param logger the logger to use.
 @return a new Process Termination Strategy instance.
 */
+ (instancetype)strategyWithProcessFetcher:(FBProcessFetcher *)processFetcher workQueue:(dispatch_queue_t)workQueue logger:(id<FBControlCoreLogger>)logger;

#pragma mark Public Methods

/**
 Terminates a Process of the provided pid

 @param processIdentifier the pid of the process to kill.
 @return a Future that resolves when the process was killed.
 */
- (FBFuture<NSNull *> *)killProcessIdentifier:(pid_t)processIdentifier;

@end

NS_ASSUME_NONNULL_END
