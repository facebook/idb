/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBiOSTargetOperation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBProcessSpawnConfiguration;

/**
 An in-memory representation of a launched application.
 This is distinct from FBLaunchedProcess, as exit codes for the process are not available.
 However, an event for when termination of the application occurs is communicated through a Future.
 */
@protocol FBLaunchedApplication <NSObject>

/**
 The Process Idenfifer of the Launched Application.
 */
@property (nonatomic, assign, readonly) pid_t processIdentifier;

/**
 A future that resolves when the Application has terminated.
 Cancelling this Future will cause the application to terminate.
 Exit code/Signal status of the launched process is not available.
 */
@property (nonatomic, strong, readonly) FBFuture<NSNull *> *applicationTerminated;

@end

/**
 An in-memory representation of a launched process.
 This is distinct from FBLaunchedApplication, as the exit code for the process is available.
 */
@protocol FBLaunchedProcess <NSObject>

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

#pragma mark Methods

/**
 Confirms that the process exited with a defined set of status codes.
 
 @param exitCodes the exit codes to check for, must not be nil.
 @return a Future with the same base behaviour as -[FBLaunchedProcess exitCode] with additional checking of codes.
 */
- (FBFuture<NSNumber *> *)exitedWithCodes:(NSSet<NSNumber *> *)exitCodes;

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
