/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBSimulator;
@class FBSimulatorSet;

/**
 A Strategy for Erasing Simulator Contents.
 */
@interface FBSimulatorEraseStrategy : NSObject

#pragma mark Public

/**
 Erases the provided Simulator, satisfying the relevant precondition of ensuring it is shutdown.

 @param simulator the Simulator to Erase.
 @return A future that resolves when the Simulator is erased.
 */
+ (nonnull FBFuture<NSNull *> *)erase:(nonnull FBSimulator *)simulator;

@end
