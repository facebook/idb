/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBLogicTestProcess;

/**
 A protocol for defining the platform-specific implementation of running an xctest process.
 */
@protocol FBXCTestProcessExecutor <NSObject>

/**
 Starts the xctest process.

 @param process the process to execute.
 @param error an error out for any error that occurs.
 @return the process identifier of the launched process.
 */
- (pid_t)logicTestProcess:(FBLogicTestProcess *)process startWithError:(NSError **)error;

/**
 Terminate the Underlying xctest process.
 
 @param process the process to terminate.
 */
- (void)terminateLogicTestProcess:(FBLogicTestProcess *)process;

/**
 Await the completion of the xctest process.

 @param process the process to await the completion of.
 @param timeout the timeout to wait for.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise
 */
- (BOOL)logicTestProcess:(FBLogicTestProcess *)process waitForCompletionWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;

/**
 The path to the Shim dylib used for reporting test output.
 */
@property (nonatomic, copy, readonly) NSString *shimPath;

/**
 The path to the Query Shim dylib used for listing test output.
 */
@property (nonatomic, copy, readonly) NSString *queryShimPath;

@end

NS_ASSUME_NONNULL_END
