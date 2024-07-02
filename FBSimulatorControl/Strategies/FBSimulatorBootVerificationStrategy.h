/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;

/**
 A Strategy for determining that a Simulator is actually usable after it is booted.
 In some circumstances it will take some time for a Simulator to be usable for standard operations.
 For instance, the first boot of a Simulator can take substantially longer than subsequent boots.
 This is mainly due to the data migrators that are run upon a fresh OS install or upgrade.
  */
@interface FBSimulatorBootVerificationStrategy : NSObject

#pragma mark Initializers

/**
 Confirms that the Simulator is in a booted state to the home screen.

 @param simulator the Simulator.
 @return a Future that resolves when the Simulator is booted to the home screen.
 */
+ (FBFuture<NSNull *> *)verifySimulatorIsBooted:(FBSimulator *)simulator;

@end

NS_ASSUME_NONNULL_END
