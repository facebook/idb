/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class NSRunningApplication;
@protocol FBProcessInfo;

/**
 Queries for Processes running on the Host.
 Should not be called from multiple threads since buffers are re-used internally.

 Sharing a Query object and guaranteeing serialization of method calls
 can be an effective way to reduce the number of allocations that are required.
 */
@interface FBProcessQuery : NSObject

/**
 A Query for obtaining all of the process information for a given processIdentifier.
 */
- (id<FBProcessInfo>)processInfoFor:(pid_t)processIdentifier;

/**
 Returns an NSArray<FBFoundProcess> of the parent.
 */
- (NSArray *)subprocessesOf:(pid_t)parent;

/**
 A Query for returning the processes with a given subtring in their launch path.
 */
- (NSArray *)processesWithLaunchPathSubstring:(NSString *)substring;

/**
 A Query for returning the processes with a given name.

 Note that this is more optimal than `processesWithLaunchPathSubstring:`
 since only the process name is fetched in the syscall.
 */
- (NSArray *)processesWithProcessName:(NSString *)processName;

/**
 A Query for returning the first named child process of the provided parent.
 */
- (pid_t)subprocessOf:(pid_t)parent withName:(NSString *)name;

/**
 A Query for returning the parent of the provided child process
 */
- (pid_t)parentOf:(pid_t)child;

/**
 A Query for returning the process identifier of the first found process with an open file of filename.
 */
- (pid_t)processWithOpenFileTo:(const char *)filename;

/**
 Returns an Array of NSRunningApplications for the provided array of FBProcessInfo.
 Any Applications that could not be found will be replaced with NSNull.null.
 */
- (NSArray *)runningApplicationsForProcesses:(NSArray *)processes;

/**
 Returns the NSRunningApplication for the provided id<FBProcessInfo>.
 Any Applications that could not be found will be replaced with NSNull.null.
 */
- (NSRunningApplication *)runningApplicationForProcess:(id<FBProcessInfo>)process;

@end
