/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBXCTestProcess;

/**
 A protocol for defining the platform-specific implementation of running an xctest process.
 */
@protocol FBXCTestProcessExecutor <NSObject>

/**
 Starts the xctest process.

 @param process the process to execute.
 @return an FBLaunchedProcess identifying the process.
 */
- (FBFuture<id<FBLaunchedProcess>> *)startProcess:(FBXCTestProcess *)process;

/**
 The path to the Shim dylib used for reporting test output.
 */
@property (nonatomic, copy, readonly) NSString *shimPath;

/**
 The path to the Query Shim dylib used for listing test output.
 */
@property (nonatomic, copy, readonly) NSString *queryShimPath;

/**
 A queue to serialize work on.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t workQueue;

@end

NS_ASSUME_NONNULL_END
