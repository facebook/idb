/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBProcessOutput;
@class FBSimulator;

/**
 FBSimulatorControl extensions to FBAgentLaunchConfiguration.
 */
@interface FBAgentLaunchConfiguration (Simulator) <FBiOSTargetFuture>

/**
 Creates a Process Output for a Simulator.

 @param simulator the simulator to create the output for.
 @return a Future that wraps an Array of the outputs.
 */
- (FBFuture<NSArray<id> *> *)createOutputForSimulator:(FBSimulator *)simulator;

@end

NS_ASSUME_NONNULL_END
