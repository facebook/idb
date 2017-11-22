/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControlAssertions.h"

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBSimulatorControlTestCase.h"

@implementation XCTestCase (FBSimulatorControlAssertions)

#pragma mark Sessions

- (void)assertShutdownSimulatorAndTerminateSession:(FBSimulator *)simulator
{
  NSError *error = nil;
  BOOL success = [[simulator shutdown] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  [[simulator.pool freeSimulator:simulator] await:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);
  [self assertSimulatorShutdown:simulator];
}

#pragma mark Strings

- (void)assertNeedle:(NSString *)needle inHaystack:(NSString *)haystack
{
  XCTAssertNotNil(needle);
  XCTAssertNotNil(haystack);
  if ([haystack rangeOfString:needle].location != NSNotFound) {
    return;
  }
  XCTFail(@"needle '%@' to be contained in haystack '%@'", needle, haystack);
}

#pragma mark Simulators

- (void)assertSimulatorBooted:(FBSimulator *)simulator
{
  XCTAssertEqual(simulator.state, FBSimulatorStateBooted);
  XCTAssertNotNil(simulator.launchdProcess);
  if (self.expectContainerProcesses) {
    XCTAssertNotNil(simulator.containerApplication);
  } else {
    XCTAssertNil(simulator.containerApplication);
  }
}

- (void)assertSimulatorShutdown:(FBSimulator *)simulator
{
  XCTAssertEqual(simulator.state, FBSimulatorStateShutdown);
  XCTAssertNil(simulator.launchdProcess);
  XCTAssertNil(simulator.containerApplication);
}

#pragma mark Processes

- (void)assertSimulator:(FBSimulator *)simulator isRunningApplicationFromConfiguration:(FBApplicationLaunchConfiguration *)launchConfiguration
{
  NSError *error = nil;
  FBProcessInfo *process = [[simulator runningApplicationWithBundleID:launchConfiguration.bundleID] await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(process);
}

#pragma mark Private

- (BOOL)expectContainerProcesses
{
  return !FBSimulatorControlTestCase.useDirectLaunching;
}

@end

@implementation FBSimulatorControlTestCase (FBSimulatorControlAssertions)

- (nullable FBSimulator *)assertObtainsSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration
{
  NSError *error = nil;
  if (![configuration checkRuntimeRequirementsReturningError:&error]) {
    NSLog(@"Configuration %@ does not meet the runtime requirements with error %@", configuration, error);
    return nil;
  }
  FBSimulator *simulator = [[self.control.pool allocateSimulatorWithConfiguration:configuration options:self.allocationOptions] await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(simulator);
  return simulator;
}

- (nullable FBSimulator *)assertObtainsSimulator
{
  return [self assertObtainsSimulatorWithConfiguration:self.simulatorConfiguration];
}

- (nullable FBSimulator *)assertObtainsBootedSimulator
{
  return [self assertObtainsBootedSimulatorWithConfiguration:self.simulatorConfiguration bootConfiguration:self.bootConfiguration];
}

- (nullable FBSimulator *)assertObtainsBootedSimulatorWithInstalledApplication:(FBApplicationBundle *)application
{
  FBSimulator *simulator = [self assertObtainsBootedSimulator];
  if (!simulator) {
    return nil;
  }
  NSError *error = nil;
  BOOL success = [[simulator installApplicationWithPath:application.path] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  return simulator;
}

- (nullable FBSimulator *)assertObtainsBootedSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration bootConfiguration:(FBSimulatorBootConfiguration *)bootConfiguration
{
  FBSimulator *simulator = [self assertObtainsSimulatorWithConfiguration:configuration];
  if (!simulator) {
    return nil;
  }

  NSError *error = nil;
  BOOL success = [[simulator bootWithConfiguration:bootConfiguration] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  return simulator;
}

- (nullable FBSimulator *)assertSimulator:(FBSimulator *)simulator installs:(FBApplicationBundle *)application
{
  NSError *error = nil;
  BOOL success = [[simulator installApplicationWithPath:application.path] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  return simulator;
}

- (nullable FBSimulator *)assertSimulator:(FBSimulator *)simulator launches:(FBApplicationLaunchConfiguration *)configuration
{
  NSError *error = nil;
  BOOL success = [[simulator launchApplication:configuration] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  [self assertSimulator:simulator isRunningApplicationFromConfiguration:configuration];

  [self assertSimulatorBooted:simulator];

  success = [[simulator launchApplication:configuration] await:&error] != nil;
  XCTAssertFalse(success);

  return simulator;
}

- (nullable FBSimulator *)assertSimulatorWithConfiguration:(FBSimulatorConfiguration *)simulatorConfiguration boots:(FBSimulatorBootConfiguration *)bootConfiguration thenLaunchesApplication:(FBApplicationLaunchConfiguration *)launchConfiguration
{
  FBSimulator *simulator = [self assertObtainsBootedSimulatorWithConfiguration:simulatorConfiguration bootConfiguration:bootConfiguration];
  return [self assertSimulator:simulator launches:launchConfiguration];
}

- (nullable FBSimulator *)assertSimulatorWithConfiguration:(FBSimulatorConfiguration *)simulatorConfiguration boots:(FBSimulatorBootConfiguration *)bootConfiguration launchesThenRelaunchesApplication:(FBApplicationLaunchConfiguration *)launchConfiguration
{
  FBSimulator *simulator = [self assertSimulatorWithConfiguration:simulatorConfiguration boots:bootConfiguration thenLaunchesApplication:launchConfiguration];
  FBProcessInfo *firstLaunch = [[simulator runningApplicationWithBundleID:launchConfiguration.bundleID] await:nil];

  NSError *error = nil;
  BOOL success = [[simulator launchOrRelaunchApplication:launchConfiguration] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  FBProcessInfo *secondLaunch = [[simulator runningApplicationWithBundleID:launchConfiguration.bundleID] await:nil];
  XCTAssertNotEqualObjects(firstLaunch, secondLaunch);

  return simulator;
}

@end
