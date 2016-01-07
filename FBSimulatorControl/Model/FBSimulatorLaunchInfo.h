/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBProcessInfo;
@class FBProcessQuery;
@class NSRunningApplication;
@class SimDevice;

/**
 Information about the a launched Simulator.

 A Launched Simulator will meet the following conditions:
 1) Have a valid launchd_sim process.
 2) If launched via a Simulator.app, have a valid Simulator.app process.
 */
@interface FBSimulatorLaunchInfo : NSObject <NSCopying>

/**
 Creates a FBSimulatorLaunchInfo object from the provided SimDevice.
 Must meet the Simulator.app process precondition.

 @param simDevice the Simulator Device to create the launch info from.
 @param query the Process Query object to obtain Process/Application info from.
 @return a FBSimulatorLaunchInfo instance if process information could be obtained, nil otherwise.
 */
+ (instancetype)launchedViaApplicationOfSimDevice:(SimDevice *)simDevice query:(FBProcessQuery *)query;

/**
 Creates a FBSimulatorLaunchInfo object from the provided SimDevice.
 Must meet the Simulator.app process precondition.

 This variant is called when it is preferable to wait a short while for process information to appear.
 This is the case when an Simulator.app has just started, but hasn't yet booted the SimDevice.

 @param simDevice the Simulator Device to create the launch info from.
 @param query the Process Query object to obtain Process/Application info from.
 @param timeout the maximum time to wait for information to appear.
 @return a FBSimulatorLaunchInfo instance if process information could be obtained, nil otherwise.
 */
+ (instancetype)launchedViaApplicationOfSimDevice:(SimDevice *)simDevice query:(FBProcessQuery *)query timeout:(NSTimeInterval)timeout;

/**
 Creates a FBSimulatorLaunchInfo object from the provided SimDevice & NSRunningApplication combination.
 Must meet the Simulator.app process precondition.

 @param simulatorApplication the Simulator Application to create the launch info from. If this conflicts with the SimDevice, nil is returned.
 @param simDevice the SimDevice to create the launch info from.
 @param query the Process Query object to obtain Process/Application info from.
 @return a FBSimulatorLaunchInfo instance if process information could be obtained, nil otherwise.
 */
+ (instancetype)launchedViaApplication:(NSRunningApplication *)simulatorApplication ofSimDevice:(SimDevice *)simDevice query:(FBProcessQuery *)query;

/**
 Creates a FBSimulatorLaunchInfo object from the provided SimDevice & NSRunningApplication combination.
 Must meet the Simulator.app process precondition.

 This variant is called when it is preferable to wait a short while for process information to appear.
 This is the case when an Simulator.app has just started, but hasn't yet booted the SimDevice.

 @param simulatorApplication the Simulator Application to create the launch info from. If this conflicts with the SimDevice, nil is returned.
 @param simDevice the SimDevice to create the launch info from.
 @param query the Process Query object to obtain Process/Application info from.
 @param timeout the maximum time to wait for information to appear.
 @return a FBSimulatorLaunchInfo instance if process information could be obtained, nil otherwise.
 */
+ (instancetype)launchedViaApplication:(NSRunningApplication *)simulatorApplication ofSimDevice:(SimDevice *)simDevice query:(FBProcessQuery *)query timeout:(NSTimeInterval)timeout;

/**
 Process Information for the Simulator.app
 */
@property (nonatomic, copy, readonly) FBProcessInfo *simulatorProcess;

/**
 Process Information for the Simulator's launchd_sim.
 */
@property (nonatomic, copy, readonly) FBProcessInfo *launchdProcess;

/**
 The NSRunningApplication instance for for the Simulator Process.
 */
@property (nonatomic, strong, readonly) NSRunningApplication *simulatorApplication;

/**
 An NSArray<id<FBSimulatorProcess>> of the currently-running launchd_sim subprocesses.
 */
- (NSArray *)launchedProcesses;

/**
 A Full Description of the Launch Info.
 */
- (NSString *)debugDescription;

/**
 A Partial Description of the Launch Info.
 */
- (NSString *)shortDescription;

@end
