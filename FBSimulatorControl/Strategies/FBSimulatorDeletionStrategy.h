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
 A Strategy for Deleting Simulators.
 */
@interface FBSimulatorDeletionStrategy : NSObject

#pragma mark Public Methods

/**
 Deletes a simulator.

 @param simulator the Simulator to Delete.
 @return a future wrapping the array of deleted simulator uuids.
 */
+ (nonnull FBFuture<NSNull *> *)delete:(nonnull FBSimulator *)simulator;

/**
 Batch operation for deleting multipole simulators.

 @param simulators the Simulators to Delete.
 @return a future wrapping the array of deleted simulator uuids.
 */
+ (nonnull FBFuture<NSNull *> *)deleteAll:(nonnull NSArray<FBSimulator *> *)simulators;

@end
