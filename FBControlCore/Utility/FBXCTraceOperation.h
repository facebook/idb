/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBSubprocess.h>
#import <FBControlCore/FBiOSTargetOperation.h>

extern const NSTimeInterval DefaultXCTraceRecordOperationTimeLimit;
extern const NSTimeInterval DefaultXCTraceRecordStopTimeout;

@class FBXCTraceRecordConfiguration;

@protocol FBControlCoreLogger;
@protocol FBiOSTarget;

/**
 Represents an `xctrace record` operation.
 */
@interface FBXCTraceRecordOperation : NSObject <FBiOSTargetOperation>

#pragma mark Initializers

/**
 Constructs an 'xctrace record' operation, of indefinite length.

 @param target the target to run against.
 @param configuration the configuration to use.
 @param logger the logger to log to.
 @return a running `xctrace record` operation.
 */
+ (nonnull FBFuture<FBXCTraceRecordOperation *> *)operationWithTarget:(nonnull id<FBiOSTarget>)target configuration:(nonnull FBXCTraceRecordConfiguration *)configuration logger:(nonnull id<FBControlCoreLogger>)logger;

- (nonnull instancetype)initWithTask:(nonnull FBSubprocess *)task traceDir:(nonnull NSURL *)traceDir configuration:(nonnull FBXCTraceRecordConfiguration *)configuration queue:(nonnull dispatch_queue_t)queue logger:(nonnull id<FBControlCoreLogger>)logger;

#pragma mark Properties

/**
 Task that wraps the operation
 */
@property (nonnull, nonatomic, readonly, strong) FBSubprocess *task;

/**
 The queue to use
 */
@property (nonnull, nonatomic, readonly, strong) dispatch_queue_t queue;

/**
 Trace output directory.
 */
@property (nonnull, nonatomic, readonly, copy) NSURL *traceDir;

/**
 The configuration of the operation.
 */
@property (nonnull, nonatomic, readonly, strong) FBXCTraceRecordConfiguration *configuration;

/**
 The logger to use.
 */
@property (nonnull, nonatomic, readonly, strong) id<FBControlCoreLogger> logger;

#pragma mark Public Methods

/**
 Stops the Operation. Waits for the trace file to be written out to disk.

 @param timeout backoff timeout to stop the operation
 @return a Future that returns the trace file if successful.
 */
- (nonnull FBFuture<NSURL *> *)stopWithTimeout:(NSTimeInterval)timeout;

/**
 Post-process a .trace file.

 @param arguments the arguments to post-process with, if relevant.
 @param traceDir Locaiton to place trace files.
 @param queue the queue to serialize on.
 @param logger the logger to log to.
 @return a delta that post-processes.
 */
+ (nonnull FBFuture<NSURL *> *)postProcess:(nullable NSArray<NSString *> *)arguments traceDir:(nonnull NSURL *)traceDir queue:(nonnull dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger;

/**
 Get the xctrace path.

 @param error an error out for any error that occurs.
 @return xctrace path
 */
+ (nullable NSString *)xctracePathWithError:(NSError * _Nullable * _Nullable)error;

@end
