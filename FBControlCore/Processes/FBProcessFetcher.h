/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <sys/sysctl.h>

#import <Foundation/Foundation.h>

@class FBProcessInfo;

@class FBFuture<T>;

/**
 Queries for processes running on the host. Not thread-safe: buffers are re-used across calls.
 */
@interface FBProcessFetcher : NSObject

/**
 A Query for obtaining all of the process information for a given processIdentifier.

 @param processIdentifier the Process Identifier to obtain process info for.
 @return an FBProcessInfo object if a process with the given identifier could be found, nil otherwise.
 */
- (nullable FBProcessInfo *)processInfoFor:(pid_t)processIdentifier;

/**
 Obtain process info for child processes.

 @param parent the Process Identifier to obtain the subprocesses of
 @return an NSArray<FBProcessInfo> of the parent's child processes.
 */
- (nonnull NSArray<FBProcessInfo *> *)subprocessesOf:(pid_t)parent;

/**
 A Query for returning the processes with a given name.

 @param processName the name of the processes to fetch.
 @return an NSArray<FBProcessInfo> of the found processes.
 */
- (nonnull NSArray<FBProcessInfo *> *)processesWithProcessName:(nonnull NSString *)processName;

/**
 A Query for returning the first named child process of the provided parent.

 @param parent the Process Identifier of the parent process.
 @param name the name of the child process.
 @return a Process Identifier of the child process if one could be found, -1 otherwise.
 */
- (pid_t)subprocessOf:(pid_t)parent withName:(nonnull NSString *)name;

/**
 A Query for returning the parent of the provided child process

 @param child the Process Identifier of the child process.
 @return a Process Identifier of the parent process if one could be found, -1 otherwise.
 */
- (pid_t)parentOf:(pid_t)child;

/**
 The first process with the file open, or -1. Considerably more expensive than the other queries.

 @param filePath the path to the file.
 */
- (pid_t)processWithOpenFileTo:(nonnull const char *)filePath;

/**
 YES if the process is in the SRUN state. NO with `error` set if the process cannot be looked up.

 @param processIdentifier process to check.
 @param error an error out for any error that occurs.
 */
- (BOOL)isProcessRunning:(pid_t)processIdentifier error:(NSError * _Nullable * _Nullable)error;

/**
 YES if the process is in the SSTOP state. NO with `error` set if the process cannot be looked up.

 @param processIdentifier process to check.
 @param error an error out for any error that occurs.
 */
- (BOOL)isProcessStopped:(pid_t)processIdentifier error:(NSError * _Nullable * _Nullable)error;

/**
 YES if a tracer is attached to the process. NO with `error` set if the process cannot be looked up.

 @param processIdentifier process to check.
 @param error an error out for any error that occurs.
 */
- (BOOL)isDebuggerAttachedTo:(pid_t)processIdentifier error:(NSError * _Nullable * _Nullable)error;

/**
 Wait for a debugger to attach to the process and the process to be up running again.

 @param processIdentifier the Process Identifier of the process.
 @return A future waiting for the debugger and process up running again.
 */
+ (nonnull FBFuture<NSNull *> *)waitForDebuggerToAttachAndContinueFor:(pid_t)processIdentifier;

/**
 Wait for process to receive SIGSTOP.

 @param processIdentifier the Process Identifier of the process.
 @return A future waiting for the process to be in SSTOP state.
 */
+ (nonnull FBFuture<NSNull *> *)waitStopSignalForProcess:(pid_t)processIdentifier;

/**
 Samples the process with /usr/bin/sample, resolving to the report text. The process is left running.

 @param processIdentifier the process identifier of the process to stackshot.
 @param queue the queue to use.
*/
+ (nonnull FBFuture<id> *)performSampleStackshotForProcessIdentifier:(pid_t)processIdentifier queue:(nonnull dispatch_queue_t)queue;

@end
