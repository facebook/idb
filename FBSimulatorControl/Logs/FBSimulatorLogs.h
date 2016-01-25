/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBSimulatorEventSink.h>

@class FBSimulator;
@class FBSimulatorSession;
@class FBWritableLog;
@class FBWritableLogBuilder;

/**
 The Name of the Syslog.
 */
extern NSString *const FBSimulatorLogNameSyslog;

/**
 The Name of the Core Simulator Log.
 */
extern NSString *const FBSimulatorLogNameCoreSimulator;

/**
 The Name of the Simulator Bootstrap.
 */
extern NSString *const FBSimulatorLogNameSimulatorBootstrap;

/**
 The Name of the Video Log
 */
extern NSString *const FBSimulatorLogNameVideo;

/**
 Exposes Simulator Logs & Diagnsotics as FBWritableLog instances.

 Instances of FBWritableLog exposed by this class are not nullable since FBWritableLog's can be empty:
 - This means that values do not have to be checked before storing in collections
 - Missing content can be inserted into the FBWritableLog instances, whilst retaining the original metadata.
 */
@interface FBSimulatorLogs : NSObject <FBSimulatorEventSink>

/**
 Creates and returns a `FBSimulatorLogs` instance.

 @param simulator the Simulator to Fetch logs for.
 @return A new `FBSimulatorLogFetcher` instance.
 */
+ (instancetype)withSimulator:(FBSimulator *)simulator;

/**
 Returns an FBWritableLogBuilder suitable for writing diagnostic log information to.
 This builder is configured to serialize to the appropriate directories.

 @return A new `FBSimulatorLogFetcher` instance.
 */
- (FBWritableLogBuilder *)logBuilder;

/**
 All of the FBWritableLog instances for the Simulator.
 Prunes empty logs.

 @return an NSArray<FBWritableLog> of all the Writable Logs associated with the Simulator.
 */
- (NSArray *)allLogs;

/**
 The syslog of the Simulator.
 */
- (FBWritableLog *)syslog;

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
 The System Log, filtered and bucketed by Processes that were launched during the Session.

 @return an NSDictionary<FBProcessInfo *, FBWritableLog> of the logs, filtered by launched process.
 */
- (NSDictionary *)launchedProcessLogs;

@end
