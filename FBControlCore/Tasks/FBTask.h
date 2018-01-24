/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBLaunchedProcess.h>

NS_ASSUME_NONNULL_BEGIN

@class FBTaskConfiguration;

/**
 Error Doman for all FBTask errors.
 */
extern NSString *const FBTaskErrorDomain;

/**
 Programmatic interface to a Task.
 */
@interface FBTask : NSObject <FBLaunchedProcess>

#pragma mark Initializers

/**
 Creates a Task with the provided configuration and starts it.

 @param configuration the configuration to use
 @return a future that resolves when the task has been started.
 */
+ (FBFuture<FBTask *> *)startTaskWithConfiguration:(FBTaskConfiguration *)configuration;

#pragma mark Accessors

/**
 A future that resolves with the exit code when the process has finished.
 Any errors will be propogated in this future.
 */
@property (nonatomic, strong, readonly) FBFuture<NSNumber *> *completed;

/**
 Returns the Process Identifier of the Launched Process.
 */
@property (nonatomic, assign, readonly) pid_t processIdentifier;

/**
 Returns the stdout of the task.
 May be called from any thread.
 The valid types for these values are the wrapped types in FBProcessOutput.
 */
@property (nonatomic, strong, nullable, readonly) id stdOut;

/**
 Returns the stdout of the task.
 May be called from any thread.
 The valid types for these values are the wrapped types in FBProcessOutput.
 */
@property (nonatomic, strong, nullable, readonly) id stdErr;

/**
 Returns the stdin of the task.
 May be called from any thread.
 The valid types for these values are the wrapped types in FBProcessInput.
 */
@property (nonatomic, strong, nullable, readonly) id stdIn;

/**
 Returns the Error associated with the task (if any). May be called from any thread.
 */
@property (nonatomic, strong, nullable, readonly) NSError *error;

@end

NS_ASSUME_NONNULL_END
