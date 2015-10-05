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
#import <FBSimulatorControl/FBSimulatorPool+Private.h>
#import <FBSimulatorControl/FBSimulatorPool.h>
#import <FBSimulatorControl/FBSimulatorSession.h>
#import <FBSimulatorControl/FBSimulatorSessionInteraction.h>

#import "FBInteractionAssertion.h"
#import "FBSimulatorControlNotificationAssertion.h"

@interface FBSimulatorControlTestCase ()

@property (nonatomic, strong, readwrite) FBSimulatorControl *control;
@property (nonatomic, strong, readwrite) FBSimulatorControlNotificationAssertion *notificationAssertion;
@property (nonatomic, strong, readwrite) FBInteractionAssertion *interactionAssertion;

@end

@implementation FBSimulatorControlTestCase

#pragma mark Overrideable Defaults

- (FBSimulatorManagementOptions)managementOptions
{
  return FBSimulatorManagementOptionsKillSpuriousSimulatorsOnFirstStart |
         FBSimulatorManagementOptionsDeleteOnFree;
}

- (FBSimulatorConfiguration *)simulatorConfiguration
{
  return FBSimulatorConfiguration.iPhone5;
}

- (NSString *)deviceSetPath
{
  return nil;
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
  [self.interactionAssertion assertPerformSuccess:session.interact.bootSimulator];
  return session;
}

#pragma mark XCTestCase

- (void)setUp
{
  FBSimulatorControlConfiguration *configuration = [FBSimulatorControlConfiguration
    configurationWithSimulatorApplication:[FBSimulatorApplication simulatorApplicationWithError:nil]
    deviceSetPath:self.deviceSetPath
    options:[self managementOptions]];

  self.control = [[FBSimulatorControl alloc] initWithConfiguration:configuration];
  self.notificationAssertion = [FBSimulatorControlNotificationAssertion new];
  self.interactionAssertion = [FBInteractionAssertion withTestCase:self];
}

- (void)tearDown
{
  [self.control.simulatorPool killAllWithError:nil];
  self.control = nil;
}

@end
