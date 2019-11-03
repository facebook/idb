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

@interface FBSimulatorLaunchTests : FBSimulatorControlTestCase

@end

@implementation FBSimulatorLaunchTests

- (FBSimulator *)doTestApplicationLaunches:(FBApplicationLaunchConfiguration *)appLaunch
{
  return [self
    assertSimulatorWithConfiguration:self.simulatorConfiguration
    boots:self.bootConfiguration
    thenLaunchesApplication:appLaunch];
}

- (FBSimulator *)doTestApplicationRelaunches:(FBApplicationLaunchConfiguration *)appLaunch
{
  return [self
    assertSimulatorWithConfiguration:self.simulatorConfiguration
    boots:self.bootConfiguration
    launchesThenRelaunchesApplication:appLaunch];
}

- (FBSimulator *)doTestApplication:(FBBundleDescriptor *)application launches:(FBApplicationLaunchConfiguration *)appLaunch
{
  FBSimulator *simulator = [self assertObtainsBootedSimulatorWithConfiguration:self.simulatorConfiguration bootConfiguration:self.bootConfiguration];
  [self assertSimulator:simulator installs:application];
  return [self assertSimulator:simulator launches:appLaunch];
}

- (void)testLaunchesSingleSimulator:(FBSimulatorConfiguration *)configuration
{
  FBSimulator *simulator = [self assertObtainsBootedSimulatorWithConfiguration:configuration bootConfiguration:self.bootConfiguration];
  if (!simulator) {
    return;
  }

  [self assertSimulatorBooted:simulator];
  [self assertShutdownSimulatorAndTerminateSession:simulator];
}

- (void)testLaunchesiPhone
{
  [self testLaunchesSingleSimulator:[FBSimulatorConfiguration withDeviceModel:SimulatorControlTestsDefaultiPhoneModel]];
}

- (void)testLaunchesiPad
{
  [self testLaunchesSingleSimulator:[FBSimulatorConfiguration withDeviceModel:SimulatorControlTestsDefaultiPadModel]];
}

- (void)testLaunchesWatch
{
  [self testLaunchesSingleSimulator:[FBSimulatorConfiguration withDeviceModel:FBDeviceModelAppleWatch42mm]];
}

- (void)testLaunchesTV
{
  [self testLaunchesSingleSimulator:[FBSimulatorConfiguration withDeviceModel:FBDeviceModelAppleTV]];
}

- (void)testLaunchesMultipleSimulators
{
  FBFuture<NSArray<FBSimulator *> *> *simulatorFutures = [FBFuture futureWithFutures:@[
    [self assertObtainsSimulatorWithConfiguration:[FBSimulatorConfiguration withDeviceModel:SimulatorControlTestsDefaultiPhoneModel]],
    [self assertObtainsSimulatorWithConfiguration:[FBSimulatorConfiguration withDeviceModel:SimulatorControlTestsDefaultiPhoneModel]],
    [self assertObtainsSimulatorWithConfiguration:[FBSimulatorConfiguration withDeviceModel:SimulatorControlTestsDefaultiPadModel]],
  ]];
  NSError *error = nil;
  NSArray<FBSimulator *> *simulators = [simulatorFutures await:&error];
  XCTAssertNil(error);
  XCTAssertTrue(simulators);

  XCTAssertEqual(self.control.set.allSimulators.count, 3u);
  FBSimulator *simulator1 = simulators[0];
  FBSimulator *simulator2 = simulators[1];
  FBSimulator *simulator3 = simulators[2];

  FBFuture *bootFuture = [FBFuture futureWithFutures:@[
    [simulator1 bootWithConfiguration:self.bootConfiguration],
    [simulator2 bootWithConfiguration:self.bootConfiguration],
    [simulator3 bootWithConfiguration:self.bootConfiguration],
  ]];
  BOOL success = [bootFuture await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  for (FBSimulator *simulator in simulators) {
    [self assertSimulatorBooted:simulator];
  }

  XCTAssertEqual([NSSet setWithArray:[simulators valueForKeyPath:@"launchdProcess.processIdentifier"]].count, 3u);

  FBFuture *shutdownFuture = [FBFuture futureWithFutures:@[
    [simulator1 shutdown],
    [simulator2 shutdown],
    [simulator3 shutdown],
  ]];
  success = [shutdownFuture await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  FBFuture *freeFuture = [FBFuture futureWithFutures:@[
    [simulator1 erase],
    [simulator2 erase],
    [simulator3 erase],
  ]];
  success = [freeFuture await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  for (FBSimulator *simulator in simulators) {
    [self assertSimulatorShutdown:simulator];
  }
}

- (void)testLaunchesSafariApplication
{
  [self doTestApplicationLaunches:self.safariAppLaunch];
}

- (void)testRelaunchesSafariApplication
{
  [self doTestApplicationRelaunches:[self safariAppLaunchWithMode:FBApplicationLaunchModeRelaunchIfRunning]];
}

- (void)testLaunchesSampleApplication
{
  [self doTestApplication:self.tableSearchApplication launches:self.tableSearchAppLaunch];
}

- (void)testCanUninstallApplication
{
  FBBundleDescriptor *application = self.tableSearchApplication;
  FBApplicationLaunchConfiguration *launch = self.tableSearchAppLaunch;
  FBSimulator *simulator = [self assertObtainsBootedSimulatorWithInstalledApplication:application];

  NSError *error = nil;
  BOOL success = [[simulator launchApplication:launch] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  [self assertSimulator:simulator isRunningApplicationFromConfiguration:launch];

  success = [[simulator uninstallApplicationWithBundleID:application.identifier] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

@end
