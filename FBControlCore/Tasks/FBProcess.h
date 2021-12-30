/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBiOSTargetOperation.h>

NS_ASSUME_NONNULL_BEGIN

static const size_t FBProcessOutputErrorMessageLength = 200;

@class FBProcessSpawnConfiguration;

/**
 A representation of a process that has been launched.
 */
@interface FBProcess <StdInType : id, StdOutType : id, StdErrType : id> : NSObject

#pragma mark Properties

/**
 The Process Idenfifer of the Launched Process.
 */
@property (nonatomic, assign, readonly) pid_t processIdentifier;

/**
 A future that resolves with the the value from waitpid(2) on termination.
 This will always resolve on completion, regardless of whether the process was signalled or exited normally.
 Cancelling this Future will have no effect. To terminate the process use the `sendSignal:` APIs.
 */
@property (nonatomic, strong, readonly) FBFuture<NSNumber *> *statLoc;

/**
 A future that resolves with the exit code upon termination.
 If the process exited abnormally then this future will error.
 Cancelling this Future will have no effect. To terminate the process use the `sendSignal:` APIs.
 */
@property (nonatomic, strong, readonly) FBFuture<NSNumber *> *exitCode;

/**
 A future that resolves when the process terminates with a signal.
 If the process exited normally then this future will error.
 Cancelling this Future will have no effect. To terminate the process use the `sendSignal:` APIs.
 */
@property (nonatomic, strong, readonly) FBFuture<NSNumber *> *signal;

/**
 The IO Object attached to the process.
 */
@property (nonatomic, strong, readonly) FBProcessSpawnConfiguration *configuration;

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


#pragma mark Initializers

/**
 The Designated Initializer.

 @param processIdentifier the process identifier of the launched process
 @param statLoc a future that will fire when the process has terminated. The value is that of waitpid(2).
 @param exitCode a future that will fire when the process exits. See -[FBProcess exitCode]
 @param signal a future that will fire when the process is signalled. See -[FBProcess signal]
 @param configuration the configuration the process was launched with.
 @param queue the queue to perform actions on.
 @return an implementation of FBProcess.
 */
- (instancetype)initWithProcessIdentifier:(pid_t)processIdentifier statLoc:(FBFuture<NSNumber *> *)statLoc exitCode:(FBFuture<NSNumber *> *)exitCode signal:(FBFuture<NSNumber *> *)signal configuration:(FBProcessSpawnConfiguration *)configuration queue:(dispatch_queue_t)queue;

/**
 Launches a process with the provided configuration.

 @param configuration the configuration to use.
 @param logger an optional logger to log process lifecycle events to.
 @return a future that resolves with the launched process once it has been started.
 */
+ (FBFuture<FBProcess *> *)launchProcessWithConfiguration:(FBProcessSpawnConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger;

#pragma mark Methods

/**
 Confirms that the process exited with a defined set of status codes.
 Cancelling this future will have no effect.
 
 @param acceptableExitCodes the exit codes to check for, must not be nil.
 @return a Future with the same base behaviour as -[FBProcess exitCode] with additional checking of codes.
 */
- (FBFuture<NSNumber *> *)exitedWithCodes:(NSSet<NSNumber *> *)acceptableExitCodes;

/**
 Signal the process.
 The future returned will resolve when the process has terminated and can be ignored if not required.

 @param signo the signal number to send.
 @return a successful Future that resolves to the signal number when the process has terminated.
 */
- (FBFuture<NSNumber *> *)sendSignal:(int)signo;

/**
 A mechanism for sending an signal to a task, backing off to a kill.
 If the process does not die before the timeout is hit, a SIGKILL will be sent.

 @param signo the signal number to send.
 @param timeout the timeout to wait before sending a SIGKILL.
 @param logger used for log information when timeout happened, may be nil.
 @return a future that resolves to the signal sent when the process has been terminated.
 */
- (FBFuture<NSNumber *> *)sendSignal:(int)signo backingOffToKillWithTimeout:(NSTimeInterval)timeout logger:(nullable id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
