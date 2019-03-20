/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetFuture.h>

NS_ASSUME_NONNULL_BEGIN

@class FBInstrumentsConfiguration;
@class FBTask;

@protocol FBControlCoreLogger;
@protocol FBiOSTarget;

/**
 The Termination Handle Type for an instruments operation.
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeInstruments;

/**
 Represents an operation of the instruments command-line.
 */
@interface FBInstrumentsOperation : NSObject <FBiOSTargetContinuation>

#pragma mark Initializers

/**
 Constructs an 'instruments' operation, of indefinite length.

 @param target the target to run against.
 @param configuration the configuration to use.
 @param logger the logger to log to.
 @return a running instruments operation.
 */
+ (FBFuture<FBInstrumentsOperation *> *)operationWithTarget:(id<FBiOSTarget>)target configuration:(FBInstrumentsConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger;

#pragma mark Properties

/**
 The file of the generated trace file.
 */
@property (nonatomic, copy, readonly) NSURL *traceFile;

/**
 The configuration of the operation.
 */
@property (nonatomic, strong, readonly) FBInstrumentsConfiguration *configuration;

/**
 The logger to use.
 */
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

#pragma mark Public Methods

/**
 Stops the Operation.
 Waits for the trace file to be written out to disk.

 @return a Future that returns the trace file if successful.
 */
- (FBFuture<NSURL *> *)stop;

@end

NS_ASSUME_NONNULL_END
