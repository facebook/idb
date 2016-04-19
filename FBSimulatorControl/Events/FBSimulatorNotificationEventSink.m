/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorNotificationEventSink.h"

NSString *const FBSimulatorDidLaunchNotification = @"FBSimulatorDidLaunchNotification";
NSString *const FBSimulatorDidTerminateNotification = @"FBSimulatorDidTerminateNotification";
NSString *const FBSimulatorContainerDidLaunchNotification = @"FBSimulatorContainerDidLaunchNotification";
NSString *const FBSimulatorContainerDidTerminateNotification = @"FBSimulatorContainerDidTerminateNotification";
NSString *const FBSimulatorBridgeDidConnectNotification = @"FBSimulatorBridgeDidConnectNotification";
NSString *const FBSimulatorBridgeDidDisconnectNotification = @"FBSimulatorBridgeDidDisconnectNotification";
NSString *const FBSimulatorApplicationProcessDidLaunchNotification = @"FBSimulatorApplicationProcessDidLaunchNotification";
NSString *const FBSimulatorApplicationProcessDidTerminateNotification = @"FBSimulatorApplicationProcessDidTerminateNotification";
NSString *const FBSimulatorAgentProcessDidLaunchNotification = @"FBSimulatorAgentProcessDidLaunchNotification";
NSString *const FBSimulatorAgentProcessDidTerminateNotification = @"FBSimulatorAgentProcessDidTerminateNotification";
NSString *const FBSimulatorTestManagerDidConnectNotification = @"FBSimulatorTestManagerDidConnectNotification";
NSString *const FBSimulatorTestManagerDidDisconnectNotification = @"FBSimulatorTestManagerDidDisconnectNotification";
NSString *const FBSimulatorGainedDiagnosticInformation = @"FBSimulatorGainedDiagnosticInformation";
NSString *const FBSimulatorStateDidChange = @"FBSimulatorStateDidChange";

NSString *const FBSimulatorExpectedTerminationKey = @"expected";
NSString *const FBSimulatorProcessKey = @"process";
NSString *const FBSimulatorDiagnosticLog = @"diagnostic_log";
NSString *const FBSimulatorBridgeKey = @"bridge";
NSString *const FBSimulatorStateKey = @"simulator_state";
NSString *const FBSimulatorTestManagerKey = @"testManager";

@interface FBSimulatorNotificationEventSink ()

@property (nonatomic, weak, readwrite) FBSimulator *simulator;

@end

@implementation FBSimulatorNotificationEventSink

#pragma mark FBSimulatorEventSink implementation

+ (instancetype)withSimulator:(FBSimulator *)simulator
{
  FBSimulatorNotificationEventSink *sink = [FBSimulatorNotificationEventSink new];
  sink.simulator = simulator;
  return sink;
}

- (void)containerApplicationDidLaunch:(FBProcessInfo *)applicationProcess
{
  [self materializeNotification:FBSimulatorContainerDidLaunchNotification userInfo:@{
    FBSimulatorProcessKey : applicationProcess
  }];
}

- (void)containerApplicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{
  [self materializeNotification:FBSimulatorContainerDidTerminateNotification userInfo:@{
    FBSimulatorExpectedTerminationKey : @(expected),
    FBSimulatorProcessKey : applicationProcess
  }];
}

- (void)bridgeDidConnect:(FBSimulatorBridge *)bridge
{
  [self materializeNotification:FBSimulatorBridgeDidConnectNotification userInfo:@{
    FBSimulatorBridgeKey : bridge,
  }];
}

- (void)bridgeDidDisconnect:(FBSimulatorBridge *)bridge expected:(BOOL)expected
{
  [self materializeNotification:FBSimulatorBridgeDidDisconnectNotification userInfo:@{
    FBSimulatorExpectedTerminationKey : @(expected),
    FBSimulatorBridgeKey : bridge,
  }];
}

- (void)simulatorDidLaunch:(FBProcessInfo *)launchdSimProcess
{
  [self materializeNotification:FBSimulatorDidLaunchNotification userInfo:@{
    FBSimulatorProcessKey : launchdSimProcess
  }];
}

- (void)simulatorDidTerminate:(FBProcessInfo *)launchdSimProcess expected:(BOOL)expected
{
  [self materializeNotification:FBSimulatorDidTerminateNotification userInfo:@{
    FBSimulatorExpectedTerminationKey : @(expected),
    FBSimulatorProcessKey : launchdSimProcess
  }];
}

- (void)agentDidLaunch:(FBAgentLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)agentProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  [self materializeNotification:FBSimulatorAgentProcessDidLaunchNotification userInfo:@{
    FBSimulatorProcessKey : agentProcess
  }];
}

- (void)agentDidTerminate:(FBProcessInfo *)agentProcess expected:(BOOL)expected
{
  [self materializeNotification:FBSimulatorAgentProcessDidTerminateNotification userInfo:@{
    FBSimulatorExpectedTerminationKey : @(expected),
    FBSimulatorProcessKey : agentProcess
  }];
}

- (void)applicationDidLaunch:(FBApplicationLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)applicationProcess
{
  [self materializeNotification:FBSimulatorApplicationProcessDidLaunchNotification userInfo:@{
    FBSimulatorProcessKey : applicationProcess,
  }];
}

- (void)applicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{
  [self materializeNotification:FBSimulatorApplicationProcessDidTerminateNotification userInfo:@{
    FBSimulatorExpectedTerminationKey : @(expected),
    FBSimulatorProcessKey : applicationProcess
  }];
}

- (void)testmanagerDidConnect:(FBTestManager *)testManager
{
  [self materializeNotification:FBSimulatorTestManagerDidConnectNotification userInfo:@{
    FBSimulatorTestManagerKey : testManager
  }];
}

- (void)testmanagerDidDisconnect:(FBTestManager *)testManager
{
  [self materializeNotification:FBSimulatorTestManagerDidDisconnectNotification userInfo:@{
    FBSimulatorTestManagerKey : testManager
  }];
}

- (void)diagnosticAvailable:(FBDiagnostic *)diagnostic
{
  [self materializeNotification:FBSimulatorGainedDiagnosticInformation userInfo:@{
    FBSimulatorDiagnosticLog : diagnostic
  }];
}

- (void)didChangeState:(FBSimulatorState)state
{
  [self materializeNotification:FBSimulatorStateDidChange userInfo:@{
    FBSimulatorStateKey : @(state)
  }];
}

- (void)terminationHandleAvailable:(id<FBTerminationHandle>)terminationHandle
{

}

#pragma mark Private

- (void)materializeNotification:(NSString *)notificationName userInfo:(NSDictionary *)userInfo
{
  NSParameterAssert(notificationName);
  NSParameterAssert(userInfo);

  [NSNotificationCenter.defaultCenter postNotificationName:notificationName object:self.simulator userInfo:userInfo];
}

@end
