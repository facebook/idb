/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBLaunchedProcess.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBFileConsumer;
@class FBTaskConfiguration;

/**
 Error Doman for all FBTask errors.
 */
extern NSString *const FBTaskErrorDomain;

/**
 Programmatic interface to a Task.
 */
@interface FBTask : NSObject <FBLaunchedProcess>

#pragma mark Initializers

/**
 Creates a Task with the provided configuration and starts it.

 @param configuration the configuration to use
 @return a task.
 */
+ (instancetype)startTaskWithConfiguration:(FBTaskConfiguration *)configuration;

#pragma mark Accessors

/**
 A future that resolves with the exit code when the process has finished.
 Any errors will be propogated in this future.
 */
- (FBFuture<NSNumber *> *)completed;

/**
 Returns the Process Identifier of the Launched Process.
 */
- (pid_t)processIdentifier;

/**
 Returns a copy of the current state of stdout. May be called from any thread.
 The types of these values are defined in FBTaskConfiguration.
 */
- (nullable id)stdOut;

/**
 Returns the stdout of the process:
 The types of these values are defined in FBTaskConfiguration.
 */
- (nullable id)stdErr;

/**
 Returns a consumer for the stdin.
 This will only exist if:
 - The Task is Configured to do so.
 - The Task is running.
 */
- (nullable id<FBFileConsumer>)stdIn;

/**
 Returns the Error associated with the task (if any). May be called from any thread.
 */
- (nullable NSError *)error;

/**
 Returns YES if the task has terminated, NO otherwise.
 */
- (BOOL)hasTerminated;

/**
 Returns YES if the task terminated without an error, NO otherwise
 */
- (BOOL)wasSuccessful;

@end

NS_ASSUME_NONNULL_END
