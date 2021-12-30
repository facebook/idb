/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#include <sys/sysctl.h>

NS_ASSUME_NONNULL_BEGIN
@class FBProcessInfo;

@class FBFuture<T>;

/**
 Queries for Processes running on the Host.
 Should not be called from multiple threads since buffers are re-used internally.

 Sharing a Query object and guaranteeing serialization of method calls
 can be an effective way to reduce the number of allocations that are required.
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
- (NSArray<FBProcessInfo *> *)subprocessesOf:(pid_t)parent;

/**
 A Query for returning the processes with a given name.

 @param processName the name of the processes to fetch.
 @return an NSArray<FBProcessInfo> of the found processes.
 */
- (NSArray<FBProcessInfo *> *)processesWithProcessName:(NSString *)processName;

/**
 A Query for returning the first named child process of the provided parent.

 @param parent the Process Identifier of the parent process.
 @param name the name of the child process.
 @return a Process Identifier of the child process if one could be found, -1 otherwise.
 */
- (pid_t)subprocessOf:(pid_t)parent withName:(NSString *)name;

/**
 A Query for returning the parent of the provided child process

 @param child the Process Identifier of the child process.
 @return a Process Identifier of the parent process if one could be found, -1 otherwise.
 */
- (pid_t)parentOf:(pid_t)child;

/**
 A Query for returning the process identifier of the first found process with an open file of filename.
 This is a operation is generally more expensive than the others.

 @param filePath the path to the file.
 @return a Process Identifier for the first process with an open file to the path, -1 otherwise.
 */
- (pid_t)processWithOpenFileTo:(const char *)filePath;

/**
 Verify if process is running

 @param processIdentifier process to check.
 @param error an error out for any error that occurs.
 @return YES if process is Runnig and error is NOT set. False if process isn't running or error is set.
 */
- (BOOL) isProcessRunning:(pid_t)processIdentifier error:(NSError **)error;

/**
 Verify if process is stopped

 @param processIdentifier process to check.
 @param error an error out for any error that occurs.
 @return YES if process is Stopped and error is NOT set. False if process isn't stopped or error is set.
 */
- (BOOL) isProcessStopped:(pid_t)processIdentifier error:(NSError **)error;

/**
 Verify if process has a debugger attached to it.

 @param processIdentifier process to check.
 @param error an error out for any error that occurs.
 @return YES if process is has a debugger attached and error is NOT set.. False if process doesn't have a debugger attached  or error is set.
 */
- (BOOL) isDebuggerAttachedTo:(pid_t)processIdentifier error:(NSError **)error;

/**
 Wait for a debugger to attach to the process and the process to be up running again.

 @param processIdentifier the Process Identifier of the process.
 @return A future waitting for the debugger and process up running again.
 */
+ (FBFuture<NSNull *> *) waitForDebuggerToAttachAndContinueFor:(pid_t)processIdentifier;

/**
 Wait for process to receive SIGSTOP.
 
 @param processIdentifier the Process Identifier of the process.
 @return A future waitting for the process to be in SSTOP state.
 */
+ (FBFuture<NSNull *> *) waitStopSignalForProcess:(pid_t) processIdentifier;
@end

NS_ASSUME_NONNULL_END
