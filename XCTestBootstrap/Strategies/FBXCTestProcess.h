/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBFileConsumer;
@protocol FBXCTestProcessExecutor;

@class FBSimulator;
@class FBXCTestProcess;

/**
 A Platform-Agnostic wrapper responsible for managing an xctest process.
 Driven by an executor, which implements the platform-specific responsibilities of launching an xctest process.
 */
@interface FBXCTestProcess : NSObject

/**
 The Designated Initializer.

 @param launchPath the Launch Path of the executable
 @param arguments the Arguments to the executable.
 @param environment the Environment Variables to set.
 @param stdOutReader the Reader of the Stdout.
 @param stdErrReader the Reader of the Stderr.
 @param executor the executor for running the test process.
 @return a new xctest process.
 */
+ (instancetype)processWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOutReader:(id<FBFileConsumer>)stdOutReader stdErrReader:(id<FBFileConsumer>)stdErrReader executor:(id<FBXCTestProcessExecutor>)executor;

/**
 Starts the Process.

 @param error an error out for any error that occurs.
 @return the PID of the launched process, -1 on error.
 */
- (pid_t)startWithError:(NSError **)error;

/**
 Terminates the process.
 */
- (void)terminate;

/**
 Waits to the process to complete.

 @param timeout the timeout in seconds to wait for the process to terminate.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)waitForCompletionWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;

/**
 To be called when a process terminates.

 @param processIdentifier the process identifier.
 @param didTimeout the timeout.
 @param exitCode the exit code.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)processDidTerminateNormallyWithProcessIdentifier:(pid_t)processIdentifier didTimeout:(BOOL)didTimeout exitCode:(int)exitCode error:(NSError **)error;

#pragma mark Properties

@property (nonatomic, copy, readonly) NSString *launchPath;
@property (nonatomic, copy, readonly) NSArray<NSString *> *arguments;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *environment;
@property (nonatomic, assign, readonly) BOOL waitForDebugger;
@property (nonatomic, strong, readonly) id<FBFileConsumer> stdOutReader;
@property (nonatomic, strong, readonly) id<FBFileConsumer> stdErrReader;

@end

NS_ASSUME_NONNULL_END
