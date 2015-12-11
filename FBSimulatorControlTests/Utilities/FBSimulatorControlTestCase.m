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
#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBSimulatorControl/FBSimulatorControlConfiguration.h>
#import <FBSimulatorControl/FBSimulatorInteraction.h>
#import <FBSimulatorControl/FBSimulatorPool+Private.h>
#import <FBSimulatorControl/FBSimulatorPool.h>
#import <FBSimulatorControl/FBSimulatorSession.h>

#import "FBSimulatorControlAssertions.h"

@interface FBSimulatorControlTestCase ()

@end

@implementation FBSimulatorControlTestCase

@synthesize control = _control;
@synthesize assert = _assert;

#pragma mark Property Overrides

- (FBSimulatorControl *)control
{
  if (!_control) {
    FBSimulatorControlConfiguration *configuration = [FBSimulatorControlConfiguration
      configurationWithSimulatorApplication:[FBSimulatorApplication simulatorApplicationWithError:nil]
      deviceSetPath:self.deviceSetPath
      options:self.managementOptions];

    NSError *error;
    FBSimulatorControl *control = [FBSimulatorControl withConfiguration:configuration error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(control);
    _control = control;
    _assert = [FBSimulatorControlNotificationAssertions withTestCase:self pool:control.simulatorPool];
  }
  return _control;
}

- (FBSimulatorControlNotificationAssertions *)assert
{
  XCTAssertNotNil(_assert, @"-[FBSimulatorControlTestCase control] should be called before -[FBSimulatorControlTestCase assert]");
  return _assert;
}

#pragma mark Helper Actions

- (FBSimulator *)allocateSimulator
{
  NSError *error = nil;
  FBSimulator *simulator = [self.control.simulatorPool allocateSimulatorWithConfiguration:self.simulatorConfiguration options:self.allocationOptions error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(simulator);
  return simulator;
}

- (FBSimulatorSession *)createSessionWithConfiguration:(FBSimulatorConfiguration *)configuration
{
  NSError *error = nil;
  FBSimulatorSession *session = [self.control createSessionForSimulatorConfiguration:configuration options:self.allocationOptions error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(session);
  return session;
}

- (FBSimulatorSession *)createSession
{
  return [self createSessionWithConfiguration:self.simulatorConfiguration];
}

- (FBSimulatorSession *)createBootedSession
{
  FBSimulatorSession *session = [self createSession];
  [self assertInteractionSuccessful:session.interact.bootSimulator];
  return session;
}

#pragma mark XCTestCase

- (void)setUp
{
  self.managementOptions = FBSimulatorManagementOptionsKillSpuriousSimulatorsOnFirstStart | FBSimulatorManagementOptionsIgnoreSpuriousKillFail;
  self.allocationOptions = FBSimulatorAllocationOptionsReuse | FBSimulatorAllocationOptionsCreate | FBSimulatorAllocationOptionsEraseOnAllocate;
  self.simulatorConfiguration = FBSimulatorConfiguration.iPhone5;
  self.deviceSetPath = nil;
}

- (void)tearDown
{
  [self.control.simulatorPool killAllWithError:nil];
  _control = nil;
  _assert = nil;
}

@end
