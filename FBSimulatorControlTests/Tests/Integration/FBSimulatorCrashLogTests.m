/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

  FBFuture<FBCrashLogInfo *> *crashLogFuture = [simulator notifyOfCrash:[FBCrashLogInfo predicateForIdentifier:@"TableSearch"]];

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
