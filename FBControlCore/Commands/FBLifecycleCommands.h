/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBiOSTargetConstants.h>
#import <FBControlCore/FBiOSTargetCommandForwarder.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Defines an interface for power related commands.
 */
@protocol FBLifecycleCommands <NSObject, FBiOSTargetCommand>

#pragma mark States

/**
 Asynchronously waits on the provided state.

 @param state the state to wait on
 @return A future that resolves when it has transitioned to the given state.
 */
- (FBFuture<NSNull *> *)resolveState:(FBiOSTargetState)state;

/**
 Asynchronously waits to leave the provided state.

 @param state the state to wait to leave
 @return A future that resolves when it has transitioned away from the given state.
 */
- (FBFuture<NSNull *> *)resolveLeavesState:(FBiOSTargetState)state;

@end

NS_ASSUME_NONNULL_END
