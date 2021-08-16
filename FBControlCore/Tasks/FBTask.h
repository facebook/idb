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
 Programmatic interface to a Task.
 */
@interface FBTask <StdInType : id, StdOutType : id, StdErrType : id> : FBLaunchedProcess <StdInType, StdOutType, StdErrType>

#pragma mark Initializers

/**
 Creates a Task with the provided configuration and starts it.

 @param configuration the configuration to use.
 @param logger an optional logger to log task lifecycle events to.
 @return a future that resolves when the task has been started.
 */
+ (FBFuture<FBTask *> *)startTaskWithConfiguration:(FBProcessSpawnConfiguration *)configuration logger:(nullable id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
