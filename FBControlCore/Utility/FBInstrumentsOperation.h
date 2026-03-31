/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBSubprocess.h>
#import <FBControlCore/FBiOSTargetOperation.h>

extern const NSTimeInterval DefaultInstrumentsOperationDuration; // Operation duration
extern const NSTimeInterval DefaultInstrumentsTerminateTimeout; // When stopping instruments with SIGINT, wait this long before SIGKILLing it
extern const NSTimeInterval DefaultInstrumentsLaunchRetryTimeout;  // Wait this long to ensure instruments started properly
extern const NSTimeInterval DefaultInstrumentsLaunchErrorTimeout; // Fail instruments if the launch error message appears within this timeout

@class FBInstrumentsConfiguration;

@protocol FBControlCoreLogger;
@protocol FBiOSTarget;

/**
 Represents an operation of the instruments command-line.
 */
@interface FBInstrumentsOperation : NSObject

#pragma mark Initializers

/**
 Constructs an 'instruments' operation, of indefinite length.

 @param target the target to run against.
 @param configuration the configuration to use.
 @param logger the logger to log to.
 @return a running instruments operation.
 */
+ (nonnull FBFuture<FBInstrumentsOperation *> *)operationWithTarget:(nonnull id<FBiOSTarget>)target configuration:(nonnull FBInstrumentsConfiguration *)configuration logger:(nonnull id<FBControlCoreLogger>)logger;

- (nonnull instancetype)initWithTask:(nonnull FBSubprocess *)task traceDir:(nonnull NSURL *)traceDir configuration:(nonnull FBInstrumentsConfiguration *)configuration queue:(nonnull dispatch_queue_t)queue logger:(nonnull id<FBControlCoreLogger>)logger;

#pragma mark Properties

@property (nonnull, nonatomic, readonly, strong) FBSubprocess *task;
@property (nonnull, nonatomic, readonly, strong) dispatch_queue_t queue;

/**
 Trace output directory.
 */
@property (nonnull, nonatomic, readonly, copy) NSURL *traceDir;

/**
 The configuration of the operation.
 */
@property (nonnull, nonatomic, readonly, strong) FBInstrumentsConfiguration *configuration;

/**
 The logger to use.
 */
@property (nonnull, nonatomic, readonly, strong) id<FBControlCoreLogger> logger;

#pragma mark Public Methods

/**
 Stops the Operation.
 Waits for the trace file to be written out to disk.

 @return a Future that returns the trace file if successful.
 */
- (nonnull FBFuture<NSURL *> *)stop;

/**
 Post-process an instruments trace.

 @param arguments the arguments to post-process with, if relevant.
 @param traceDir Locaiton to place trace files.
 @param queue the queue to serialize on.
 @param logger the logger to log to.
 @return a delta that post-processes.
 */
+ (nonnull FBFuture<NSURL *> *)postProcess:(nullable NSArray<NSString *> *)arguments traceDir:(nonnull NSURL *)traceDir queue:(nonnull dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger;

@end
