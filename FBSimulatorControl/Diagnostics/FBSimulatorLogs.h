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
@class FBDiagnostic;
@class FBDiagnosticBuilder;

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
 The Name of the Screenshot Log.
 */
extern NSString *const FBSimulatorLogNameScreenshot;

/**
 Exposes Simulator Logs & Diagnsotics as FBDiagnostic instances.

 Instances of FBDiagnostic exposed by this class are not nullable since FBDiagnostic's can be empty:
 - This means that values do not have to be checked before storing in collections
 - Missing content can be inserted into the FBDiagnostic instances, whilst retaining the original metadata.
 */
@interface FBSimulatorLogs : NSObject <FBSimulatorEventSink>

/**
 Creates and returns a `FBSimulatorLogs` instance.

 @param simulator the Simulator to Fetch logs for.
 @return A new `FBSimulatorLogs` instance for the provided Simulator.
 */
+ (instancetype)withSimulator:(FBSimulator *)simulator;

/**
 The FBDiagnostic Instance from which all other logs are derived.
 */
- (FBDiagnostic *)base;

/**
 The syslog of the Simulator.
 */
- (FBDiagnostic *)syslog;

/**
 The Log for CoreSimulator.
 */
- (FBDiagnostic *)coreSimulator;

/**
 The Bootstrap of the Simulator's launchd_sim.
 */
- (FBDiagnostic *)simulatorBootstrap;

/**
 A Video of the Simulator
 */
- (FBDiagnostic *)video;

/**
 A Screenshot of the Simulator.
 */
- (FBDiagnostic *)screenshot;

/**
 Crash logs of all the subprocesses that have crashed in the Simulator after the specified date.

 @param date the earliest to search for crash reports. If nil will find reports regardless of date.
 @return an NSArray<FBDiagnostic *> of all the applicable crash reports.
 */
- (NSArray *)subprocessCrashesAfterDate:(NSDate *)date;

/**
 Crashes that occured in the Simulator since the last booting of the Simulator.

 @return an NSArray<FBDiagnostic *> of crashes that occured for user processes since the last boot.
 */
- (NSArray *)userLaunchedProcessCrashesSinceLastLaunch;

/**
 The System Log, filtered and bucketed for each process that was launched by the user.

 @return an NSDictionary<FBProcessInfo *, FBDiagnostic> of the logs, filtered by launched process.
 */
- (NSDictionary *)launchedProcessLogs;

/**
 All of the FBDiagnostic instances for the Simulator.
 Prunes empty logs.

 @return an NSArray<FBDiagnostic> of all the Diagnostics associated with the Simulator.
 */
- (NSArray *)allLogs;

@end
