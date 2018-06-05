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

@interface FBSimulatorCrashLogTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorCrashLogTests

- (void)testAppCrashLogIsFetched
{
  if (FBSimulatorControlTestCase.isRunningOnTravis) {
    return;
  }

  FBSimulator *simulator = [self assertObtainsBootedSimulatorWithInstalledApplication:self.tableSearchApplication];
  NSString *path = [[NSBundle bundleForClass: self.class] pathForResource:@"libShimulator" ofType:@"dylib"];
  FBApplicationLaunchConfiguration *configuration = [self.tableSearchAppLaunch injectingLibrary:path];
  FBApplicationLaunchConfiguration *appLaunch = [configuration withEnvironmentAdditions:@{@"SHIMULATOR_CRASH_AFTER" : @"1"}];

  FBFuture<FBCrashLogInfo *> *crashLogFuture = [simulator notifyOfCrash:[FBCrashLogInfo predicateForName:@"TableSearch"]];

  NSError *error = nil;
  BOOL success = [[simulator launchApplication:appLaunch] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  FBCrashLogInfo *crashLog = [crashLogFuture awaitWithTimeout:FBControlCoreGlobalConfiguration.slowTimeout error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(crashLog);
  XCTAssertEqualObjects(crashLog.identifier, @"TableSearch");
  XCTAssertTrue([[NSString stringWithContentsOfFile:crashLog.crashPath encoding:NSUTF8StringEncoding error:nil] containsString:@"NSFileManager stringWithFormat"]);
}

@end
