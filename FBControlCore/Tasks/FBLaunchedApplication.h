/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>

/**
 An in-memory representation of a launched application.
 This is distinct from FBSubprocess, as exit codes for the process are not available.
 However, an event for when termination of the application occurs is communicated through a Future.
 */
@protocol FBLaunchedApplication <NSObject>

/**
 The Bundle Idenfifer of the Launched Application.
 */
@property (nonnull, nonatomic, readonly, copy) NSString *bundleID;

/**
 The Process Idenfifer of the Launched Application.
 */
@property (nonatomic, readonly, assign) pid_t processIdentifier;

/**
 A future that resolves when the Application has terminated.
 Cancelling this Future will cause the application to terminate.
 Exit code/Signal status of the launched process is not available.
 */
@property (nonnull, nonatomic, readonly, strong) FBFuture<NSNull *> *applicationTerminated;

@end
