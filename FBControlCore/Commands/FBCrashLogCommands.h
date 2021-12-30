/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBiOSTargetCommandForwarder.h>
#import <FBControlCore/FBFileContainer.h>

NS_ASSUME_NONNULL_BEGIN

@class FBCrashLogInfo;
@class FBCrashLogStore;

/**
 Commands for obtaining crash logs.
 */
@protocol FBCrashLogCommands <NSObject, FBiOSTargetCommand>

/**
 Obtains all of the crash logs matching a given predicate.

 @param predicate the predicate to match against.
 @param useCache YES to use the cached crash logs, NO to re-fetch. Pass YES when significant events have happened.
 @return a Future that resolves with crash logs.
 */
- (FBFuture<NSArray<FBCrashLogInfo *> *> *)crashes:(NSPredicate *)predicate useCache:(BOOL)useCache;

/**
 Notifies when a Crash Log becomes available for a given predicate.

 @param predicate the predicate to match against.
 @return a Future that will resolve when the first predicate matching the crash becomes available.
 */
- (FBFuture<FBCrashLogInfo *> *)notifyOfCrash:(NSPredicate *)predicate;

/**
 Prunes all of the crashes that may be cached that match the given predicate.

 @param predicate the predicate to match against.
 @return a Future that will resolve with the pruned crash logs.
 */
- (FBFuture<NSArray<FBCrashLogInfo *> *> *)pruneCrashes:(NSPredicate *)predicate;

/**
 Returns a "File View" of the crash logs.

 @return a Future context that resolves with the file commands.
 */
- (FBFutureContext<id<FBFileContainer>> *)crashLogFiles;

@end

NS_ASSUME_NONNULL_END

