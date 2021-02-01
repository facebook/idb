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

/**
 An in-memory representation of a launched application.
 Distinct from FBLaunchedProcess, as the exit code is not available, but completion is.
 */
@protocol FBLaunchedApplication <NSObject, FBiOSTargetOperation>

/**
 The Process Idenfifer of the Launched Application.
 */
@property (nonatomic, assign, readonly) pid_t processIdentifier;

@end

/**
 An in-memory representation of a launched process.
 Distinct from FBLaunchedApplication, as the exit code is not available.
 */
@protocol FBLaunchedProcess <NSObject>

/**
 The Process Idenfifer of the Launched Process.
 */
@property (nonatomic, assign, readonly) pid_t processIdentifier;

/**
 A future that resolves with the exit code upon termination.
 */
@property (nonatomic, strong, readonly) FBFuture<NSNumber *> *exitCode;

@end

NS_ASSUME_NONNULL_END
