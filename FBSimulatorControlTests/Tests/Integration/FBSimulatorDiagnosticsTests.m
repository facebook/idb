/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBSimulatorControlAssertions.h"
#import "FBSimulatorControlFixtures.h"
#import "FBSimulatorControlTestCase.h"

@interface FBSimulatorDiagnosticsTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorDiagnosticsTests

- (void)assertFindsNeedle:(NSString *)needle fromHaystackBlock:( NSString *(^)(void) )block
{
  __block NSString *haystack = nil;
  BOOL foundLog = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.slowTimeout untilTrue:^ BOOL {
    haystack = block();
    return haystack != nil;
  }];
  if (!foundLog) {
    XCTFail(@"Failed to find haystack log");
    return;
  }

  [self assertNeedle:needle inHaystack:haystack];
}

- (void)testAppCrashLogIsFetched
{
  if (FBSimulatorControlTestCase.isRunningOnTravis) {
    return;
  }

  FBSimulator *simulator = [self obtainBootedSimulator];
  FBApplicationLaunchConfiguration *appLaunch = [self.tableSearchAppLaunch.injectingShimulator withEnvironmentAdditions:@{@"SHIMULATOR_CRASH_AFTER" : @"1"}];

  [self assertInteractionSuccessful:[[simulator.interact installApplication:self.tableSearchApplication] launchApplication:appLaunch]];

  // Shimulator sends an unrecognized selector to NSFileManager to cause a crash.
  // The CrashReporter service is a background service as it will symbolicate in a separate process.
  [self assertFindsNeedle:@"-[NSFileManager stringWithFormat:]" fromHaystackBlock:^ NSString * {
    return [[simulator.diagnostics.userLaunchedProcessCrashesSinceLastLaunch firstObject] asString];
  }];
}

- (void)testSystemLog
{
  if (FBSimulatorControlTestCase.isRunningOnTravis) {
    return;
  }

  FBSimulator *simulator = [self obtainBootedSimulator];

  [self assertFindsNeedle:@"syslogd" fromHaystackBlock:^ NSString * {
    return simulator.diagnostics.syslog.asString;
  }];
}

- (void)testLaunchedApplicationLogs
{
  if (FBSimulatorControlTestCase.isRunningOnTravis) {
    return;
  }

  FBSimulator *simulator = [self obtainBootedSimulator];
  FBApplicationLaunchConfiguration *appLaunch = self.tableSearchAppLaunch.injectingShimulator;
  [self assertInteractionSuccessful:[[simulator.interact installApplication:self.tableSearchApplication] launchApplication:appLaunch]];

  [self assertFindsNeedle:@"Shimulator" fromHaystackBlock:^ NSString * {
    return [[simulator.diagnostics.launchedProcessLogs.allValues firstObject] asString];
  }];
}

@end
