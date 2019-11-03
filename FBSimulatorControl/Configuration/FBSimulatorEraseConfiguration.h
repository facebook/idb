/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The Action Type for an Log Tail.
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeErase;

/**
 An FBiOSTargetFuture for Erasing a Simulator.
 */
@interface FBSimulatorEraseConfiguration : FBiOSTargetFutureSimple <FBiOSTargetFuture>

@end

NS_ASSUME_NONNULL_END
