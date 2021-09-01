/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBProcessFetcher.h>
#import <FBControlCore/FBFuture.h>

NS_ASSUME_NONNULL_BEGIN

@class FBBinaryDescriptor;
@class FBProcessInfo;
@class NSRunningApplication;

/**
 Higher-Level wrappers around FBProcessFetcher
 */
@interface FBProcessFetcher (Helpers)

/**
 A that determines if the provided process is currently running.

 @param processIdentifier the process identifier of the process.
 @param error an error out for any error that occurs
 @return YES if a matching process is found, NO otherwise.
 */
- (BOOL)processIdentifierExists:(pid_t)processIdentifier error:(NSError **)error;

/**
 Uses the receiver to wait for the termination of a process identifier.

 @param queue the queue to poll on.
 @param processIdentifier the pid of the process to wait for.
 @return a Future that resolves when the process dies.
 */
- (FBFuture<NSNull *> *)onQueue:(dispatch_queue_t)queue waitForProcessIdentifierToDie:(pid_t)processIdentifier;

@end

NS_ASSUME_NONNULL_END
