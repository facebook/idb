/*
 * Copyright (c) Facebook, Inc. and its affiliates.
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
 This can be for a variety of reasons, but represents the time take for a Simulator to boot to the OS.
 In particular, the first boot of a Simulator after creation can take some time during the run of datamigrator.
 */
@interface FBSimulatorBootVerificationStrategy : NSObject

#pragma mark Initializers

/**
 The Designated Initializer.

 @param simulator the Simulator.
 @return a Boot Verification Strategy.
 */
+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator;

#pragma mark Public Methods.

/**
 Verifies that the Simulator is booted.
 It can also be called on a Simulator after it has been booted for some time
 as a means of verifying the Simulator is in a known-good state.

 @return a Future that resolves when the Simulator is in a known-good state.
 */
- (FBFuture<NSNull *> *)verifySimulatorIsBooted;

@end

NS_ASSUME_NONNULL_END
