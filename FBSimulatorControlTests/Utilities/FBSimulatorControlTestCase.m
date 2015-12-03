/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControlTestCase.h"

#import <FBSimulatorControl/FBSimulator.h>
#import <FBSimulatorControl/FBSimulatorApplication.h>
#import <FBSimulatorControl/FBSimulatorConfiguration.h>
#import <FBSimulatorControl/FBSimulatorControl+Private.h>
#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBSimulatorControl/FBSimulatorControlConfiguration.h>
#import <FBSimulatorControl/FBSimulatorInteraction.h>
#import <FBSimulatorControl/FBSimulatorPool+Private.h>
#import <FBSimulatorControl/FBSimulatorPool.h>
#import <FBSimulatorControl/FBSimulatorSession.h>

#import "FBSimulatorControlAssertions.h"

@implementation FBSimulatorControlTestCase

@synthesize assert = _assert;

#pragma mark Overrideable Defaults

- (FBSimulatorControl *)control
{
  if (!_control) {
    FBSimulatorControlConfiguration *configuration = [FBSimulatorControlConfiguration
      configurationWithSimulatorApplication:[FBSimulatorApplication simulatorApplicationWithError:nil]
      deviceSetPath:self.deviceSetPath
      options:self.managementOptions];

    _control = [[FBSimulatorControl alloc] initWithConfiguration:configuration];
  }
  return _control;
}

- (FBSimulatorControlAssertions *)assert
{
  if (!_assert) {
    _assert = [FBSimulatorControlAssertions withTestCase:self];
  }
  return _assert;
}

#pragma mark Helper Actions

- (FBSimulator *)allocateSimulator
{
  NSError *error = nil;
  FBSimulator *simulator = [self.control.simulatorPool allocateSimulatorWithConfiguration:self.simulatorConfiguration error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(simulator);
  return simulator;
}

- (FBSimulatorSession *)createSession
{
  NSError *error = nil;
  FBSimulatorSession *session = [self.control createSessionForSimulatorConfiguration:self.simulatorConfiguration error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(session);
  return session;
}

- (FBSimulatorSession *)createBootedSession
{
  FBSimulatorSession *session = [self createSession];
  [self.assert interactionSuccessful:session.interact.bootSimulator];
  return session;
}

#pragma mark XCTestCase

- (void)setUp
{
  self.managementOptions = FBSimulatorManagementOptionsKillSpuriousSimulatorsOnFirstStart | FBSimulatorManagementOptionsIgnoreSpuriousKillFail | FBSimulatorManagementOptionsDeleteOnFree | FBSimulatorManagementOptionsKillSpuriousCoreSimulatorServices;
  self.simulatorConfiguration = FBSimulatorConfiguration.iPhone5;
  self.deviceSetPath = nil;
}

- (void)tearDown
{
  [self.control.simulatorPool killAllWithError:nil];
  self.control = nil;
}

@end
