/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBTerminationHandle.h>

/**
 The Default Timeout for Tasks
 */
extern NSTimeInterval const FBTaskDefaultTimeout;

/**
 Programmatic interface to a Task.
 */
@protocol FBTask <NSObject, FBTerminationHandle>

/**
 Runs the reciever, returning when the Task has completed or when the timeout is hit.

 @param timeout the the maximum time to evaluate the task.
 @return the reciever, for chaining.
 */
- (instancetype)startSynchronouslyWithTimeout:(NSTimeInterval)timeout;

/**
 Asynchronously launches the task, returning immediately after the Task has launched.

 @param handler the handler to call when the Task has terminated.
 @return the reciever, for chaining.
 */
- (instancetype)startAsynchronouslyWithTerminationHandler:(void (^)(id<FBTask> task))handler;

/**
 Asynchronously launches the task, returning immediately after the Task has launched.

 @return the reciever, for chaining.
 */
- (instancetype)startAsynchronously;

/**
 Returns the Process Identifier of the Launched Process.
 */
- (NSInteger)processIdentifier;

/**
 Returns a copy of the current state of stdout. May be called from any thread.
 */
- (NSString *)stdOut;

/**
 Returns a copy of the current state of stderr. May be called from any thread.
 */
- (NSString *)stdErr;

/**
 Returns the Error associated with the shell command (if any). May be called from any thread.
 */
- (NSError *)error;

@end
