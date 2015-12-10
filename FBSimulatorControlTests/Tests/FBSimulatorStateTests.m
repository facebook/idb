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
#import "FBSimulatorControlFixtures.h"

@interface FBSimulatorStateTests : XCTestCase

@property (nonatomic, strong, readwrite) FBSimulatorSessionStateGenerator *generator;

@end

@implementation FBSimulatorStateTests

- (void)setUp
{
  FBSimulatorControlTests_SimDevice_Double *device = [FBSimulatorControlTests_SimDevice_Double new];
  device.state = FBSimulatorStateCreating;
  device.UDID = [NSUUID UUID];
  device.name = @"iPhoneMega";

  FBSimulator *simulator = [FBSimulator new];
  simulator.device = (id)device;

  FBSimulatorSession *session = [FBSimulatorSession new];
  session.simulator = simulator;
  self.generator = [FBSimulatorSessionStateGenerator generatorWithSession:(id)session];
}

- (void)tearDown
{
  self.generator = nil;
}

- (void)assertState:(FBSimulatorSessionState *)state changes:(NSArray *)changes
{
  NSArray *actualStates = [state.changesToSimulatorState.reverseObjectEnumerator.allObjects valueForKey:@"simulatorState"];
  XCTAssertEqualObjects(actualStates, changes);
}

- (void)testLastAppLaunch
{
  FBApplicationLaunchConfiguration *firstAppLaunch = [self appLaunch1];
  FBApplicationLaunchConfiguration *secondAppLaunch = [self appLaunch2];

  FBApplicationLaunchConfiguration *lastLaunchedApp = [[[[[[[self.generator
    updateLifecycle:FBSimulatorSessionLifecycleStateStarted]
    update:firstAppLaunch withProcessIdentifier:12]
    remove:firstAppLaunch.application.binary]
    update:secondAppLaunch withProcessIdentifier:42]
    remove:secondAppLaunch.application.binary]
    currentState]
    lastLaunchedApplication];

  XCTAssertNotNil(lastLaunchedApp);
  XCTAssertNotEqualObjects(firstAppLaunch, lastLaunchedApp);
  XCTAssertEqualObjects(secondAppLaunch, lastLaunchedApp);
}

- (void)testAppendsDiagnosticInformationToState
{
  FBApplicationLaunchConfiguration *appLaunch = [self appLaunch1];

  FBSimulatorSessionState *state = [[[[self.generator
    updateLifecycle:FBSimulatorSessionLifecycleStateStarted]
    updateWithDiagnosticNamed:@"GOOD TIMES" data:@"YEP"]
    update:appLaunch withProcessIdentifier:12]
    currentState];

  XCTAssertEqual(state.diagnostics.count, 1u);
  XCTAssertEqualObjects(@"YEP", state.diagnostics[@"GOOD TIMES"]);
}

- (void)testAppendsDiagnosticInformationToRunningProcess
{
  FBApplicationLaunchConfiguration *appLaunch = [self appLaunch1];

  NSString *diagnostic = @"I AM SOME SPOOKY INFO";
  FBSimulatorSessionState *state = [[[[self.generator
    updateLifecycle:FBSimulatorSessionLifecycleStateStarted]
    update:appLaunch withProcessIdentifier:12]
    update:appLaunch.application withDiagnosticNamed:@"SECRIT" data:diagnostic]
    currentState];

  XCTAssertEqualObjects(diagnostic, [state diagnosticNamed:@"SECRIT" forApplication:appLaunch.application]);
  XCTAssertEqual(state.allProcessDiagnostics.count, 1u);
  XCTAssertEqualObjects(diagnostic, state.allProcessDiagnostics[@"SECRIT"]);
}

- (void)testAppendsDiagnosticInformationToKilledProcess
{
  FBApplicationLaunchConfiguration *appLaunch = [self appLaunch1];

  NSString *diagnostic = @"I AM SOME SPOOKY INFO";
  FBSimulatorSessionState *state = [[[[[self.generator
    updateLifecycle:FBSimulatorSessionLifecycleStateStarted]
    update:appLaunch withProcessIdentifier:12]
    remove:appLaunch.application.binary]
    update:appLaunch.application withDiagnosticNamed:@"SECRIT" data:diagnostic]
    currentState];

  XCTAssertEqualObjects(diagnostic, [state diagnosticNamed:@"SECRIT" forApplication:appLaunch.application]);
  XCTAssertEqual(state.allProcessDiagnostics.count, 1u);
  XCTAssertEqualObjects(diagnostic, state.allProcessDiagnostics[@"SECRIT"]);
}

- (void)testChangesToSimulatorState
{
  FBSimulatorSessionState *state = [[[[[[[self.generator
    updateLifecycle:FBSimulatorSessionLifecycleStateStarted]
    updateSimulatorState:FBSimulatorStateCreating]
    updateSimulatorState:FBSimulatorStateBooting]
    updateSimulatorState:FBSimulatorStateBooted]
    updateSimulatorState:FBSimulatorStateShuttingDown]
    updateSimulatorState:FBSimulatorStateShutdown]
    currentState];

  [self assertState:state changes:@[
    @(FBSimulatorStateCreating),
    @(FBSimulatorStateBooting),
    @(FBSimulatorStateBooted),
    @(FBSimulatorStateShuttingDown),
    @(FBSimulatorStateShutdown)
  ]];
}

@end
