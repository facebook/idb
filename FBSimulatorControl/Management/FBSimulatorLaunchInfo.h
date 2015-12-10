/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@protocol FBProcessInfo;
@class FBProcessQuery;
@class NSRunningApplication;
@class SimDevice;

/**
 Information about the current launch of a Simulator.
 */
@interface FBSimulatorLaunchInfo : NSObject

/**
 Creates a FBSimulatorLaunchInfo object from the provided SimDevice.

 @param simDevice the Simulator Device to create the launch info from.
 @param query the Process Query object to obtain Process/Application info from.
 @return a FBSimulatorLaunchInfo instance if process information could be obtained, nil otherwise.
 */
+ (instancetype)fromSimDevice:(SimDevice *)simDevice query:(FBProcessQuery *)query;

/**
 Creates a FBSimulatorLaunchInfo object from the provided SimDevice.
 Since it may take a short while for process info to update a timeout can be provided.

 @param simDevice the Simulator Device to create the launch info from.
 @param query the Process Query object to obtain Process/Application info from.
 @param timeout the maximum time to wait for information to appear.
 @return a FBSimulatorLaunchInfo instance if process information could be obtained, nil otherwise.
 */
+ (instancetype)fromSimDevice:(SimDevice *)simDevice query:(FBProcessQuery *)query timeout:(NSTimeInterval)timeout;

/**
 Process Information for the Simulator.app
 */
@property (nonatomic, copy, readonly) id<FBProcessInfo> simulatorProcess;

/**
 Process Information for the Simulator's launchd_sim.
 */
@property (nonatomic, copy, readonly) id<FBProcessInfo> launchdProcess;

/**
 The NSRunningApplication instance for for the Simulator Process.
 */
@property (nonatomic, strong, readonly) NSRunningApplication *simulatorApplication;

/**
 An NSArray<id<FBSimulatorProcess>> of the currently-running launchd_sim subprocesses.
 */
- (NSArray *)launchedProcesses;

@end
