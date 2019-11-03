/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBXCTestProcess;

@protocol FBDataConsumer;

/**
 A protocol for defining the platform-specific implementation of running an xctest process.
 */
@protocol FBXCTestProcessExecutor <NSObject>

#pragma mark Methods

/**
 Starts the xctest process.

 @return an FBLaunchedProcess identifying the process.
 */
- (FBFuture<id<FBLaunchedProcess>> *)startProcessWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment stdOutConsumer:(id<FBDataConsumer>)stdOutConsumer stdErrConsumer:(id<FBDataConsumer>)stdErrConsumer;

#pragma mark Properties

/**
 The Path to the xctest executable.
 */
@property (nonatomic, copy, readonly) NSString *xctestPath;

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
