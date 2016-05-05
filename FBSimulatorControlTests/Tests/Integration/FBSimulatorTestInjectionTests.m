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

#import "CoreSimulatorDoubles.h"
#import "FBSimulatorControlTestCase.h"
#import "FBSimulatorPoolTestCase.h"
#import "FBSimulatorControlFixtures.h"
#import "FBSimulatorControlAssertions.h"

@interface FBSimulatorTestInjection : FBSimulatorControlTestCase

@end

@implementation FBSimulatorTestInjection

- (void)testInjectsApplicationTestIntoSampleApp
{
  FBSimulator *simulator = [self obtainBootedSimulator];
  id<FBInteraction> interaction = [[simulator.interact
    installApplication:self.tableSearchApplication]
    startTestRunnerLaunchConfiguration:self.tableSearchAppLaunch testBundlePath:self.applicationTestBundlePath];

  [self assertInteractionSuccessful:interaction];
}

- (void)testInjectsApplicationTestIntoSafari
{
  FBSimulator *simulator = [self obtainBootedSimulator];
  id<FBInteraction> interaction = [simulator.interact
    startTestRunnerLaunchConfiguration:self.safariAppLaunch testBundlePath:self.applicationTestBundlePath];

  [self assertInteractionSuccessful:interaction];
}

@end
