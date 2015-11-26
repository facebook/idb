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
 The Process Identifier of the Simulator's launchd_sim. -1 if it is not running
 */
@property (nonatomic, assign, readonly) pid_t launchdSimProcessIdentifier;

/**
 Returns an NSArray<id<FBProcessInfo>> of the subprocesses of launchd_sim.
 */
@property (nonatomic, copy, readonly) NSArray *launchedProcesses;

@end
