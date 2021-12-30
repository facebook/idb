/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBProcess.h>
#import <FBControlCore/FBiOSTargetOperation.h>

extern const NSTimeInterval DefaultXCTraceRecordOperationTimeLimit;
extern const NSTimeInterval DefaultXCTraceRecordStopTimeout;

NS_ASSUME_NONNULL_BEGIN

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
+ (FBFuture<FBXCTraceRecordOperation *> *)operationWithTarget:(id<FBiOSTarget>)target configuration:(FBXCTraceRecordConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger;

- (instancetype)initWithTask:(FBProcess *)task traceDir:(NSURL *)traceDir configuration:(FBXCTraceRecordConfiguration *)configuration queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger;

#pragma mark Properties

/**
 Task that wraps the operation
 */
@property (nonatomic, strong, readonly) FBProcess *task;

/**
 The queue to use
 */
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

/**
 Trace output directory.
 */
@property (nonatomic, copy, readonly) NSURL *traceDir;

/**
 The configuration of the operation.
 */
@property (nonatomic, strong, readonly) FBXCTraceRecordConfiguration *configuration;

/**
 The logger to use.
 */
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

#pragma mark Public Methods

/**
 Stops the Operation. Waits for the trace file to be written out to disk.
 
 @param timeout backoff timeout to stop the operation
 @return a Future that returns the trace file if successful.
 */
- (FBFuture<NSURL *> *)stopWithTimeout:(NSTimeInterval)timeout;

/**
 Post-process a .trace file.

 @param arguments the arguments to post-process with, if relevant.
 @param traceDir Locaiton to place trace files.
 @param queue the queue to serialize on.
 @param logger the logger to log to.
 @return a delta that post-processes.
 */
+ (FBFuture<NSURL *> *)postProcess:(nullable NSArray<NSString *> *)arguments traceDir:(NSURL *)traceDir queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger;

/**
 Get the xctrace path.

 @param error an error out for any error that occurs.
 @return xctrace path
 */
+ (NSString *)xctracePathWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
