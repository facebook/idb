/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <OCMock/OCMock.h>

#import <FBSimulatorControl/FBProcessLaunchConfiguration.h>
#import <FBSimulatorControl/FBSimulator.h>
#import <FBSimulatorControl/FBSimulatorApplication.h>
#import <FBSimulatorControl/FBSimulatorControlConfiguration.h>
#import <FBSimulatorControl/FBSimulatorPool.h>
#import <FBSimulatorControl/FBSimulatorSession.h>
#import <FBSimulatorControl/FBSimulatorSessionState+Queries.h>
#import <FBSimulatorControl/FBSimulatorSessionStateGenerator.h>

#import "FBSimulatorSessionStateAssertion.h"

@interface FBSimulatorStateTests : XCTestCase

@property (nonatomic, strong, readwrite) FBSimulatorSessionStateGenerator *generator;

@end

@implementation FBSimulatorStateTests

- (void)setUp
{
  OCMockObject *session = [OCMockObject mockForClass:FBSimulatorSession.class];
  OCMockObject *simulator = [OCMockObject mockForClass:FBSimulator.class];
  [[[session stub] andReturn:simulator] simulator];
  [(FBSimulator *)[[simulator stub] andReturnValue:OCMOCK_VALUE(FBSimulatorStateCreating)] state];

  self.generator = [FBSimulatorSessionStateGenerator generatorWithSession:(id)session];
}

- (void)tearDown
{
  self.generator = nil;
}

- (FBApplicationLaunchConfiguration *)appLaunch1
{
  return [FBApplicationLaunchConfiguration
    configurationWithApplication:[FBSimulatorApplication simulatorApplicationWithError:nil]
    arguments:@[@"LAUNCH1"]
    environment:@{@"FOO" : @"BAR"}];
}

- (FBApplicationLaunchConfiguration *)appLaunch2
{
  return [FBApplicationLaunchConfiguration
    configurationWithApplication:[FBSimulatorApplication simulatorApplicationWithError:nil]
    arguments:@[@"LAUNCH2"]
    environment:@{@"BING" : @"BONG"}];
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
  XCTAssertEqual(state.allDiagnostics.count, 1);
  XCTAssertEqualObjects(diagnostic, state.allDiagnostics[@"SECRIT"]);
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
  XCTAssertEqual(state.allDiagnostics.count, 1);
  XCTAssertEqualObjects(diagnostic, state.allDiagnostics[@"SECRIT"]);
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

  [[FBSimulatorSessionStateAssertion forState:state] assertChangesToSimulatorState:@[
    @(FBSimulatorStateCreating),
    @(FBSimulatorStateBooting),
    @(FBSimulatorStateBooted),
    @(FBSimulatorStateShuttingDown),
    @(FBSimulatorStateShutdown)
  ]];
}

@end
