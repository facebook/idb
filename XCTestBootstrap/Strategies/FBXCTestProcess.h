/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBControlCoreLogger;
@protocol FBXCTestProcessExecutor;

/**
 A Platform-Agnostic wrapper responsible for managing an xctest process.
 Driven by an executor, which implements the platform-specific responsibilities of launching an xctest process.
 */
@interface FBXCTestProcess : NSObject <FBLaunchedProcess>

/**
 The fully completed xctest process. The value here mirrors `exitCode`.
 However observing this future will mean that you are observing the additional crash detection.
 */
@property (nonatomic, assign, readonly) FBFuture<NSNumber *> *completedNormally;

/**
 Starts the Execution of an fbxctest process, returning an object that accounts for various parts of the execution through the "completedNormally" Future:
 - Checks that the exit code is a valid one for xctest.
 - If the test process crashes, an attempt is made find the crash log and attach it to the error of the future.
 - If the test process fails to complete within a timeout, an attempt is made to sample the process and attach it to the error of the future.

 @param launchPath the Launch Path of the executable
 @param arguments the Arguments to the executable.
 @param environment the Environment Variables to set.
 @param stdOutConsumer the Consumer of the launched xctest process stdout.
 @param stdErrConsumer the Consumer of the launched xctest process stderr.
 @param executor the executor for running the test process.
 @param logger the logger to log to.
 @return a future that resolves with the launched process.
 */
+ (FBFuture<FBXCTestProcess *> *)startWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOutConsumer:(id<FBDataConsumer>)stdOutConsumer stdErrConsumer:(id<FBDataConsumer>)stdErrConsumer executor:(id<FBXCTestProcessExecutor>)executor timeout:(NSTimeInterval)timeout logger:(id<FBControlCoreLogger>)logger;

/**
 Ensures that the process completes within the given timeout.
 "Completion" means that the process's exit code has been resolved successfully.
 If the test process fails to complete within a timeout, an attempt is made to sample the process and attach it to the error of the future.

 @param process the process to inspect.
 @param timeout the timeout in seconds.
 @param queue the queue to use.
 @param logger the logger to log to.
 @return a future that resolves with the exit code.
 */
+ (FBFuture<NSNumber *> *)ensureProcess:(id<FBLaunchedProcess>)process completesWithin:(NSTimeInterval)timeout queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger;

/**
 Describe the exit code, if an error.

 @param exitCode the exit code of the xctest process.
 @return a String representing the error, nil otherwise.
*/
+ (nullable NSString *)describeFailingExitCode:(int)exitCode;

@end

NS_ASSUME_NONNULL_END
