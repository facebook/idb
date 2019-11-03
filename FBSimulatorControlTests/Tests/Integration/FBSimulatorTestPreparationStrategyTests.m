/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <XCTestBootstrap/XCTestBootstrap.h>
#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBSimulatorControlAssertions.h"
#import "FBSimulatorControlFixtures.h"
#import "FBSimulatorControlTestCase.h"

@interface FBSimulatorTestPreparationStrategyTests : FBSimulatorControlTestCase
@end

@implementation FBSimulatorTestPreparationStrategyTests

- (void)testSimulatorPreparation
{
  FBSimulator *simulator = [self assertObtainsBootedSimulator];
  FBSimulatorTestPreparationStrategy *strategy = [FBSimulatorTestPreparationStrategy strategyWithTestLaunchConfiguration:self.defaultTestLaunch workingDirectory:NSTemporaryDirectory()];

  NSError *error = nil;
  FBTestRunnerConfiguration *configuration = [[strategy prepareTestWithIOSTarget:simulator] await:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(configuration);

  NSDictionary *env = configuration.launchEnvironment;
  XCTAssertNotNil(configuration);
  XCTAssertNotNil(configuration.testRunner);
  XCTAssertNotNil(configuration.launchArguments);
  XCTAssertNotNil(env);
  XCTAssertTrue([env[@"AppTargetLocation"] containsString:@"MobileSafari.app/MobileSafari"]);
  XCTAssertTrue([env[@"TestBundleLocation"] containsString:@"iOSUnitTestFixture.xctest"]);
}

- (FBTestLaunchConfiguration *)defaultTestLaunch
{
  return [[FBTestLaunchConfiguration
    configurationWithTestBundlePath:self.iOSUnitTestBundlePath]
    withApplicationLaunchConfiguration:self.safariAppLaunch];
}

@end
