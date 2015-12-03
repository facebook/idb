/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulatorInteraction.h>

@class FBAgentLaunchConfiguration;
@class FBSimulatorBinary;

@interface FBSimulatorInteraction (Agents)

/**
 Launches the provided Agent with the given Configuration.
 */
- (instancetype)launchAgent:(FBAgentLaunchConfiguration *)agentLaunch;

/**
 Launches the provided Agent.
 */
- (instancetype)killAgent:(FBSimulatorBinary *)agent;

@end
