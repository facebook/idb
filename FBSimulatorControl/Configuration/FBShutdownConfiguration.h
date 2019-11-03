/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The Action Type for the Shutting Down.
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeListShutdown;

/**
 The Target Action Class for Shutting down a Simulator.
 */
@interface FBShutdownConfiguration : FBiOSTargetFutureSimple <FBiOSTargetFuture>

@end

NS_ASSUME_NONNULL_END
