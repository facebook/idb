/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulator.h>

@interface FBSimulator (Queries)

/**
 Returns YES if the reciever has an active launchd_sim process.
 The Simulator.app is mostly a shell, with launchd_sim launching all the Simulator services.
 */
- (BOOL)hasActiveLaunchdSim;

/**
 Returns an NSArray<id<FBSimulatorProcess>> of the subprocesses of launchd_sim.
 */
- (NSArray *)launchedProcesses;

@end
