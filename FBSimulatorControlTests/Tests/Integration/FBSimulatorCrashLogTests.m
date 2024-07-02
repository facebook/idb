/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
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
  FBApplicationLaunchConfiguration *appLaunch = self.tableSearchAppLaunch;
  NSMutableDictionary<NSString *, NSString *> *environment = [appLaunch.environment mutableCopy];
  environment[@"SHIMULATOR_CRASH_AFTER"] = @"1";
  environment[@"DYLD_INSERT_LIBRARIES"] = path;
  appLaunch = [[FBApplicationLaunchConfiguration alloc]
    initWithBundleID:appLaunch.bundleID
    bundleName:appLaunch.bundleName
    arguments:appLaunch.arguments
    environment:environment
    waitForDebugger:NO
    io:appLaunch.io
    launchMode:appLaunch.launchMode];

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
