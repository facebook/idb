/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import "FBTerminationHandle.h"

/**
 Error Doman for all FBTaskExecutor errors
 */
extern NSString *const FBTaskExecutorErrorDomain;

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

/**
 Executes shell commands and return the results of standard output/error.
 */
@interface FBTaskExecutor : NSObject

/**
 Returns the shared `FBTaskExecutor` instance.
 */
+ (instancetype)sharedInstance;

/**
 Creates a Task for execution.
 When the task is launched it will be retained until the task has terminated.
 Terminate must be called to free up resources.

 @param launchPath the Executable Path to launch.
 @param arguments the arguments to send to the launched tasks.
 @return a Task ready to be started.
 */
- (id<FBTask>)taskWithLaunchPath:(NSString *)launchPath arguments:(NSArray *)arguments;

/**
 Creates a Shell Command for execution. May be executed according to the `id<FBTask>` API.

 @param command the Shell Command to execute. File Paths must be quoted or escaped. Must not be nil.
 @return a Shell Task ready to be started.
 */
- (id<FBTask>)shellTask:(NSString *)command;

/**
 @see executeShellCommand:returningError:
 */
- (NSString *)executeShellCommand:(NSString *)command;

/**
 Executes the given command using the shell and returns the result.
 The returned string has leading/trailing whitespace and new lines trimmed.
 Will error if the time taken to execute the command exceeds the default timeout.

 @param command The shell command to execute. File Paths must be quoted or escaped. Must not be nil.
 @param error NSError byref to be populated if an error occurs while executing the command. May be nil. Populates the userInfo with stdout.
 @return The stdout from the command. Returns nil if an Error occured.
 */
- (NSString *)executeShellCommand:(NSString *)command returningError:(NSError **)error;

/**
 Repeatedly runs the given command, passing the output to the block.
 When the block returns YES or the timeout is reached, the method will exit.
 If a non-zero exit code is returned, the method will exit.

 @param command the Command String to run.
 @param the Error Outparam for any error that occures
 @param block the predicate to verify stdOut against
 @return YES if the untilTrue block returns YES before the timeout, NO otherwise.
 */
- (BOOL)repeatedlyRunCommand:(NSString *)command withError:(NSError **)error untilTrue:( BOOL(^)(NSString *stdOut) )block;

/**
 Escapes the given path, so that it can be placed into a shell command string.

 @param path the File Path to escape
 @return a shell-escaped file path
 */
+ (NSString *)escapePathForShell:(NSString *)path;

@end
