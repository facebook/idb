/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

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
 The

 @param target the target to run against.
 @param instrumentName the name of the instrument.
 @param application Bundle ID for the target application.
 @param variables Environment variables to be applied while profiling.
 @param appArguments Command-line argument to be passed to the app being profiled.
 @param duration the duration of the instrument operation.
 @param logger the logger to log to.
 @return a running instruments operation.
 */
+ (FBFuture<FBInstrumentsOperation *> *)operationWithTarget:(id<FBiOSTarget>)target instrumentName:(NSString *)instrumentName targetApplication:(nullable NSString *)application environmentVariables:(NSDictionary<NSString *, NSString *> *)variables appArguments:(NSArray<NSString *> *)appArguments duration:(NSTimeInterval)duration logger:(id<FBControlCoreLogger>)logger;

#pragma mark Properties

/**
 The file of the generated trace file.
 */
@property (nonatomic, copy, readonly) NSURL *traceFile;

#pragma mark Public Methods

/**
 Stops the Operation.
 Waits for the trace file to be written out to disk.

 @return a Future that returns the trace file if successful.
 */
- (FBFuture<NSURL *> *)stop;

@end

NS_ASSUME_NONNULL_END
