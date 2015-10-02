/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBProcessLaunchConfiguration+Helpers.h>
#import <FBSimulatorControl/FBSimulator.h>
#import <FBSimulatorControl/FBSimulatorLogs+Private.h>
#import <FBSimulatorControl/FBSimulatorLogs.h>
#import <FBSimulatorControl/FBSimulatorSession.h>
#import <FBSimulatorControl/FBSimulatorSessionInteraction.h>
#import <FBSimulatorControl/FBWritableLog.h>
#import <FBSimulatorControl/NSRunLoop+SimulatorControlAdditions.h>

#import "FBSimulatorControlAssertions.h"
#import "FBSimulatorControlFixtures.h"
#import "FBSimulatorControlTestCase.h"

@interface FBSimulatorLogsTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorLogsTests

- (void)flakyOnTravis_testAppCrashLogIsFetched
{
  FBSimulatorSession *session = [self createBootedSession];
  FBApplicationLaunchConfiguration *appLaunch = [[FBSimulatorControlFixtures.tableSearchAppLaunch
    injectingShimulator]
    withEnvironmentAdditions:@{@"SHIMULATOR_CRASH_AFTER" : @"1"}];

  [self.assert interactionSuccessful:[[session.interact installApplication:appLaunch.application] launchApplication:appLaunch]];

  // Shimulator sends an unrecognized selector to NSFileManager to cause a crash.
  // The CrashReporter service is a background service as it will symbolicate in a separate process.
  NSString *needle = @"-[NSFileManager stringWithFormat:]";
  NSPredicate *predicate = [NSPredicate predicateWithBlock:^ BOOL (FBSimulatorSessionLogs *sessionLogs, NSDictionary *_) {
    NSArray *crashLogs = [sessionLogs subprocessCrashes];
    if (crashLogs.count != 1) {
      return NO;
    }
    FBWritableLog *log = crashLogs[0];
    return [log.asString rangeOfString:needle].location != NSNotFound;
  }];

  BOOL metCondition = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:60 untilTrue:^ BOOL {
    return [predicate evaluateWithObject:session.logs];
  }];
  XCTAssertTrue(metCondition, @"Expected to find crash logs, but none were found. Contents of directory are %@", session.logs.diagnosticReportsContents);
}

@end
