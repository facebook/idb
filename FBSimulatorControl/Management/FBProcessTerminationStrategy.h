/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@protocol FBSimulatorLogger;
@class FBProcessInfo;
@class FBProcessQuery;

/**
 A Strategy that defines how to terminate Processes.
 */
@interface FBProcessTerminationStrategy : NSObject

/**
 Uses kill(2) to terminate Applications.

 @param processQuery the Process Query object to use.
 @param signo the signal number to use when killing. See signal(3) for more info
 @param logger the logger to use.
 @return a new Process Termination Strategy instance.
 */
+ (instancetype)withProcessKilling:(FBProcessQuery *)processQuery signo:(int)signo logger:(id<FBSimulatorLogger>)logger;

/**
 Uses methods on NSRunningApplication to terminate Applications.
 Uses kill(2) otherwise

 @param processQuery the Process Query object to use.
 @param signo the signal number to use when killing. See signal(3) for more info
 @param logger the logger to use.
 @return a new Process Termination Strategy instance.
 */
+ (instancetype)withRunningApplicationTermination:(FBProcessQuery *)processQuery signo:(int)signo logger:(id<FBSimulatorLogger>)logger;;

/**
 Terminates a Process of the provided Process Info.

 @param process the process to terminate, must not be nil.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)killProcess:(FBProcessInfo *)process error:(NSError **)error;

/**
 Terminates a number of Processes of the provided Process Info Array.

 @param processes an NSArray<FBProcessInfo> of processes to terminate.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)killProcesses:(NSArray *)processes error:(NSError **)error;

@end
