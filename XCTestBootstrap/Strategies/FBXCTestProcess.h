/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBControlCoreLogger;
@protocol FBCrashLogCommands;

/**
 A Platform-Agnostic utility class responsible for managing an xctest process.
 Driven by an executor, which implements the platform-specific responsibilities of launching an xctest process.
 */
@interface FBXCTestProcess : NSObject

/**
 Ensures that the process completes within the given timeout.
 Additionally, crash log detection may be optionally added.
 "Completion" means that the process's exit code has been resolved successfully, but the exit code is not checked.
 If the test process fails to complete within a timeout, an attempt is made to sample the process and attach it to the error of the future.

 @param process the process to inspect.
 @param timeout the timeout in seconds.
 @param crashLogCommands if provided, crash log detection will be added. This implementation will be used for finding crash logs. If nil, then no crash detection will be used.
 @param queue the queue to use.
 @param logger the logger to log to.
 @return a future that resolves with the exit code.
 */
+ (FBFuture<NSNumber *> *)ensureProcess:(FBProcess *)process completesWithin:(NSTimeInterval)timeout crashLogCommands:(nullable id<FBCrashLogCommands>)crashLogCommands queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger;

/**
 Describe the exit code, if an error.

 @param exitCode the exit code of the xctest process.
 @return a String representing the error, nil otherwise.
*/
+ (nullable NSString *)describeFailingExitCode:(int)exitCode;

@end

NS_ASSUME_NONNULL_END
