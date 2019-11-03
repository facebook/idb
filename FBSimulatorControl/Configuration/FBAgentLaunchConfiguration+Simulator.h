/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

@end

NS_ASSUME_NONNULL_END
