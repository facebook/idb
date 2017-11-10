/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBProcessFetcher.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

@class FBBinaryDescriptor;
@class FBProcessInfo;
@class NSRunningApplication;

/**
 Higher-Level wrappers around FBProcessFetcher
 */
@interface FBProcessFetcher (Helpers)

/**
 Obtains the Future Process.
 */
- (FBFuture<FBProcessInfo *> *)onQueue:(dispatch_queue_t)queue processInfoFor:(pid_t)processIdentifier timeout:(NSTimeInterval)timeout;

/**
 A Query for obtaining all of the process information for a given processIdentifier, with a timeout.

 @param processIdentifier the Process Identifier to obtain process info for.
 @param timeout a timeout for finding the process information in.
 @return an FBProcessInfo object if a process with the given identifier could be found, nil otherwise.
 */
- (nullable FBProcessInfo *)processInfoFor:(pid_t)processIdentifier timeout:(NSTimeInterval)timeout;

/**
 Queryies for the Process Info for a launchd job dictionary.

 @param jobDictionary the Job Dictionary to use.
 @return the Process Info of the Job Dictionary, if available.
 */
- (nullable FBProcessInfo *)processInfoForJobDictionary:(NSDictionary<NSString *, id> *)jobDictionary;

/**
 Queries for the Process Info for a launchd job dictionary.
 Jobs without valid processes will not be included in the resulting array.

 @param jobDictionaries the Job Dictionaries to obtain process info for.
 @return the Process Info for the Jobs that could be obtained.
 */
- (NSArray<FBProcessInfo *> *)processInfoForJobDictionaries:(NSArray<NSDictionary<NSString *, id> *> *)jobDictionaries;

/**
 Retrieves the Process Info for an array of NSRunningApplication objects.
 Jobs without valid processes will not be included in the resulting array.

 @param runningApplications the Running Applications array to obtain process info for.
 @return the Process Info for the Jobs that could be obtained.
 */
- (NSArray<FBProcessInfo *> *)processInfoForRunningApplications:(NSArray<NSRunningApplication *> *)runningApplications;

/**
 A that determines if the provided process is currently running.

 @param process the Process to look for
 @param error an error out for any error that occurs
 @return YES if a matching process is found, NO otherwise.
 */
- (BOOL)processExists:(FBProcessInfo *)process error:(NSError **)error;

/**
 Uses the reciever to wait for the termination of a process.

 @param queue the queue to poll on.
 @param process the process to wait for.
 @return a Future that resolves when the process dies.
 */
- (FBFuture<NSNull *> *)onQueue:(dispatch_queue_t)queue waitForProcessToDie:(FBProcessInfo *)process;

/**
 Returns an Array of NSRunningApplications for the provided array of FBProcessInfo.

 @param processes the process to find the NSRunningApplication instances for.
 @return an NSArray<NSRunningApplication>. Any Applications that could not be found will be replaced with NSNull.null.
 */
- (NSArray<NSRunningApplication *> *)runningApplicationsForProcesses:(NSArray *)processes;

/**
 Returns the NSRunningApplication for the provided FBProcessInfo *.

 @param process the application process to obtain the NSRunningApplication instance for.
 @return a FBProcessInfo for the running application, nil if one could not be found.
 */
- (nullable NSRunningApplication *)runningApplicationForProcess:(FBProcessInfo *)process;

/**
 Constructs a Predicate that matches Processes for the launchPath.

 @param launchPath the launch path to search for.
 @return an NSPredicate that operates on an Collection of FBProcessInfo *.
 */
+ (NSPredicate *)processesWithLaunchPath:(NSString *)launchPath;

/**
 Constructs a Predicate that matches against an Application.
 Installing an Application on a Simulator will result in it having a different launch path
 since the Application Bundle is moved into the Simulator's data directory.
 This predicate takes the discrepancy in launch paths into account.

 @param binary the binary of the Application to search for.
 @return an NSPredicate that operates on an Collection of id<FBProcessInfo>.
 */
+ (NSPredicate *)processesForBinary:(FBBinaryDescriptor *)binary;

@end

NS_ASSUME_NONNULL_END
