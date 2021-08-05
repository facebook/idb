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
 This is distinct from FBLaunchedApplication, as exit information is not available.
 However, termination of the application is communicated via a Future.
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
 This is distinct from FBLaunchedApplication, as exit information is available.
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
 */
@property (nonatomic, strong, readonly) FBFuture<NSNumber *> *statLoc;

/**
 A future that resolves with the exit code upon termination.
 If the process exited abnormally then this future will error.
 */
@property (nonatomic, strong, readonly) FBFuture<NSNumber *> *exitCode;

/**
 A future that resolves when the process terminates with a signal.
 If the process exited normally then this future will error.
 */
@property (nonatomic, strong, readonly) FBFuture<NSNumber *> *signal;

/**
 The IO Object attached to the process.
 */
@property (nonatomic, strong, readonly) FBProcessSpawnConfiguration *configuration;

#pragma mark Methods

/**
 Signal the process.
 The future returned will resolve when the process has terminated and can be ignored if not required.

 @param signo the signal number to send.
 @return a successful Future that resolves to the signal number when the process has terminated.
 */
- (FBFuture<NSNumber *> *)sendSignal:(int)signo;

@end

NS_ASSUME_NONNULL_END
