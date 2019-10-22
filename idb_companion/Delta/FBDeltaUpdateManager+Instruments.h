/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import "FBDeltaUpdateManager.h"

NS_ASSUME_NONNULL_BEGIN

/**
 Contains the incremental state of an instruments operation.
 */
@interface FBInstrumentsDelta : NSObject

/**
 The location of the trace file is located.
 Is nil when the file is not yet written to.
 */
@property (nonatomic, copy, nullable, readonly) NSURL *traceFile;

/**
 The log output data.
 */
@property (nonatomic, copy, readonly) NSString *logOutput;

@end

typedef FBDeltaUpdateManager<FBInstrumentsDelta *, FBInstrumentsOperation *, FBInstrumentsConfiguration *> FBInstrumentsManager;

/**
 Manages multiple instrument sessions for one target.
 */
@interface FBDeltaUpdateManager (Instruments)

#pragma mark Public Methods

/**
 A manager of instruments operations

 @param target the target to use.
 @return a Delta Update Manager for instruments.
 */
+ (FBInstrumentsManager *)instrumentsManagerWithTarget:(id<FBiOSTarget>)target;

/**
 Post-process an instruments trace, wrapped in deltas

 @param arguments the arguments to post-process with, if relevant.
 @param delta the delta to apply to.
 @param queue the queue to serialize on.
 @return a delta that post-processes.
 */
+ (FBFuture<FBInstrumentsDelta *> *)postProcess:(nullable NSArray<NSString *> *)arguments delta:(FBInstrumentsDelta *)delta queue:(dispatch_queue_t)queue;

/**
 Post-process an instruments trace.

 @param arguments the arguments to post-process with, if relevant.
 @param traceFile the file to apply.
 @param queue the queue to serialize on.
 @param logger the logger to log to.
 @return a delta that post-processes.
 */
+ (FBFuture<NSURL *> *)postProcess:(nullable NSArray<NSString *> *)arguments traceFile:(NSURL *)traceFile queue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
