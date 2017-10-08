/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBTerminationHandle.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBFileConsumer;
@class FBTaskConfiguration;

/**
 Error Doman for all FBTask errors.
 */
extern NSString *const FBTaskErrorDomain;

/**
 The Termination Handle Type for a Task.
 */
extern FBTerminationHandleType const FBTerminationHandleTypeTask;

/**
 Programmatic interface to a Task.
 */
@interface FBTask : NSObject <FBTerminationHandle>

#pragma mark Initializers

/**
 Creates a Task with the provided configuration.

 @param configuration the configuration to use
 @return a task.
 */
+ (instancetype)taskWithConfiguration:(FBTaskConfiguration *)configuration;

#pragma mark Starting a Task

/**
 Runs the reciever, returning when the Task has completed or when the timeout is hit.
 If the timeout is reached, the process will be terminated.

 @param timeout the the maximum time to evaluate the task.
 @return the reciever, for chaining.
 */
- (instancetype)startSynchronouslyWithTimeout:(NSTimeInterval)timeout;

/**
 Asynchronously launches the task, returning immediately after the Task has launched.

 @Param terminationQueue the queue to call the termination handler on.
 @param handler the handler to call when the Task has terminated.
 @return the reciever, for chaining.
 */
- (instancetype)startAsynchronouslyWithTerminationQueue:(dispatch_queue_t)terminationQueue handler:(void (^)(FBTask *task))handler;

/**
 Asynchronously launches the task, returning immediately after the Task has launched.

 @return the reciever, for chaining.
 */
- (instancetype)startAsynchronously;

#pragma mark Awaiting Completion

/**
 Runs the reciever, returning when the Task has completed or when the timeout is hit.
 If the timeout is reached, the process will not be automatically terminated.

 @param timeout the the maximum time to evaluate the task.
 @return the reciever, for chaining.
 */
- (BOOL)waitForCompletionWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;

#pragma mark Accessors

/**
 Returns the Process Identifier of the Launched Process.
 */
- (pid_t)processIdentifier;

/**
 Returns the Exit Code of the Process
 */
- (int)exitCode;

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
