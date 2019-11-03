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
@class FBSimulatorApplicationOperation;

/**
 Simulator-Specific Application Commands.
 */
@protocol FBSimulatorApplicationCommands <FBApplicationCommands, FBiOSTargetCommand>

#pragma mark Querying Application State

/**
 Returns the Process Info for a Application by Bundle ID.

 @param bundleID the Bundle ID to fetch an installed application for.
 @return A future that resolves with the process info of the running application.
 */
- (FBFuture<FBProcessInfo *> *)runningApplicationWithBundleID:(NSString *)bundleID;

@end

/**
 Implementation of FBApplicationCommands for Simulators.
 */
@interface FBSimulatorApplicationCommands : NSObject <FBSimulatorApplicationCommands>

@end

NS_ASSUME_NONNULL_END
