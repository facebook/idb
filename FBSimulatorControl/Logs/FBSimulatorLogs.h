/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBSimulator;
@class FBSimulatorSession;
@class FBWritableLog;

/**
 Exposes Simulator Logs & Diagnsotics as FBWritableLog instances.
 */
@interface FBSimulatorLogs : NSObject

/**
 Creates and returns a `FBSimulatorLogs` instance.

 @param simulator the Simulator to Fetch logs for.
 @return A new `FBSimulatorLogFetcher` instance.
 */
+ (instancetype)withSimulator:(FBSimulator *)simulator;

/**
 The syslog of the Simulator.
 */
- (FBWritableLog *)systemLog;

/**
 The Log for CoreSimulator.
 */
- (FBWritableLog *)coreSimulator;

/**
 The Bootstrap of the Simulator's launchd_sim.
 */
- (FBWritableLog *)simulatorBootstrap;

/**
 Crash logs of all the subprocesses that have crashed in the Simulator after the specified date.

 @param date the earliest to search for crash reports. If nil will find reports regardless of date.
 @return an NSArray<FBWritableLog *> of all the applicable crash reports.
 */
- (NSArray *)subprocessCrashesAfterDate:(NSDate *)date;

/**
 Crashes that occured in the Simulator since the last booting of the Simulator.

 @return an NSArray<FBWritableLog *> of crashes that occured for user processes since the last boot.
 */
- (NSArray *)userLaunchedProcessCrashesSinceLastLaunch;

/**
 The System Log, filtered and bucketed by Applications that were launched during the Session. Returned as an NSDictionary<NSString *, FBWritableLog *>

 @return an NSDictionary<FBProcessInfo *, FBWritableLog> of the logs, filtered by launched process.
 */
- (NSDictionary *)launchedApplicationLogs;

@end
