/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBLaunchedProcess.h>

NS_ASSUME_NONNULL_BEGIN

static const size_t FBTaskOutputErrorMessageLength = 200;

@class FBProcessSpawnConfiguration;

/**
 Error Doman for all FBTask errors.
 */
extern NSString *const FBTaskErrorDomain;

/**
 Programmatic interface to a Task.
 */
@interface FBTask <StdInType : id, StdOutType : id, StdErrType : id> : NSObject <FBLaunchedProcess>

#pragma mark Initializers

/**
 Creates a Task with the provided configuration and starts it.

 @param configuration the configuration to use.
 @param acceptableExitCodes the set of status codes that apply to the "completed" future.
 @param logger an optional logger to use for logging.
 @return a future that resolves when the task has been started.
 */
+ (FBFuture<FBTask *> *)startTaskWithConfiguration:(FBProcessSpawnConfiguration *)configuration acceptableExitCodes:(nullable NSSet<NSNumber *> *)acceptableExitCodes logger:(nullable id<FBControlCoreLogger>)logger;

#pragma mark Public Methods

/**
 Signal the process.
 The future returned will resolve when the process has terminated and can be ignored if not required.

 @param signo the signal number to send.
 @return a successful Future that resolves to the signal number when the process has terminated.
 */
- (FBFuture<NSNumber *> *)sendSignal:(int)signo;

#pragma mark Accessors

/**
 A future that resolves with the exit code when the process has finished.
 Cancelling this future will send a SIGTERM to the launched process.
 If the process exited with an exit code different than the acceptable
 values then the future will resolve to failure otherwise it will resolve to success.
 Any errors will also be surfaced in this future.
 */
@property (nonatomic, strong, readonly) FBFuture<NSNumber *> *completed;

/**
 Returns the stdin of the task.
 May be called from any thread.
 The valid types for these values are the wrapped types in FBProcessInput.
 */
@property (nonatomic, strong, nullable, readonly) StdInType stdIn;

/**
 Returns the stdout of the task.
 May be called from any thread.
 The valid types for these values are the wrapped types in FBProcessOutput.
 */
@property (nonatomic, strong, nullable, readonly) StdOutType stdOut;

/**
 Returns the stdout of the task.
 May be called from any thread.
 The valid types for these values are the wrapped types in FBProcessOutput.
 */
@property (nonatomic, strong, nullable, readonly) StdErrType stdErr;

@end

NS_ASSUME_NONNULL_END
