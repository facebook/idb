/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorNotificationEventSink.h"

FBSimulatorNotificationName const FBSimulatorNotificationNameDidLaunch = @"FBSimulatorNotificationNameDidLaunch";
FBSimulatorNotificationName const FBSimulatorNotificationNameDidTerminate = @"FBSimulatorNotificationNameDidTerminate";
FBSimulatorNotificationName const FBSimulatorNotificationNameSimulatorApplicationDidLaunch = @"FBSimulatorNotificationNameSimulatorApplicationDidLaunch";
FBSimulatorNotificationName const FBSimulatorNotificationNameSimulatorApplicationDidTerminate = @"FBSimulatorNotificationNameSimulatorApplicationDidTerminate";
FBSimulatorNotificationName const FBSimulatorNotificationNameConnectionDidConnect = @"FBSimulatorNotificationNameConnectionDidConnect";
FBSimulatorNotificationName const FBSimulatorNotificationNameConnectionDidDisconnect = @"FBSimulatorNotificationNameConnectionDidDisconnect";
FBSimulatorNotificationName const FBSimulatorNotificationNameApplicationProcessDidLaunch = @"FBSimulatorNotificationNameApplicationProcessDidLaunch";
FBSimulatorNotificationName const FBSimulatorNotificationNameApplicationProcessDidTerminate = @"FBSimulatorNotificationNameApplicationProcessDidTerminate";
FBSimulatorNotificationName const FBSimulatorNotificationNameAgentProcessDidLaunch = @"FBSimulatorNotificationNameAgentProcessDidLaunch";
FBSimulatorNotificationName const FBSimulatorNotificationNameAgentProcessDidTerminate = @"FBSimulatorNotificationNameAgentProcessDidTerminate";
FBSimulatorNotificationName const FBSimulatorNotificationNameTestManagerDidConnect = @"FBSimulatorNotificationNameTestManagerDidConnect";
FBSimulatorNotificationName const FBSimulatorNotificationNameTestManagerDidDisconnect = @"FBSimulatorNotificationNameTestManagerDidDisconnect";
FBSimulatorNotificationName const FBSimulatorNotificationNameGainedDiagnosticInformation = @"FBSimulatorNotificationNameGainedDiagnosticInformation";
FBSimulatorNotificationName const FBSimulatorNotificationNameStateDidChange = @"FBSimulatorNotificationNameStateDidChange";

NSString *const FBSimulatorNotificationUserInfoKeyExpectedTermination = @"expected";
NSString *const FBSimulatorNotificationUserInfoKeyProcess = @"process";
NSString *const FBSimulatorNotificationUserInfoKeyDiagnostic = @"diagnostic_log";
NSString *const FBSimulatorNotificationUserInfoKeyConnection = @"connection";
NSString *const FBSimulatorNotificationUserInfoKeyState = @"simulator_state";
NSString *const FBSimulatorNotificationUserInfoKeyTestManager = @"testManager";
NSString *const FBSimulatorNotificationUserInfoKeyWaitingForDebugger = @"waiting_for_debugger";

@interface FBSimulatorNotificationNameEventSink ()

@property (nonatomic, weak, readwrite) FBSimulator *simulator;

@end

@implementation FBSimulatorNotificationNameEventSink

#pragma mark FBSimulatorEventSink implementation

+ (instancetype)withSimulator:(FBSimulator *)simulator
{
  FBSimulatorNotificationNameEventSink *sink = [FBSimulatorNotificationNameEventSink new];
  sink.simulator = simulator;
  return sink;
}

- (void)containerApplicationDidLaunch:(FBProcessInfo *)applicationProcess
{
  [self materializeNotification:FBSimulatorNotificationNameSimulatorApplicationDidLaunch userInfo:@{
    FBSimulatorNotificationUserInfoKeyProcess : applicationProcess
  }];
}

- (void)containerApplicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{
  [self materializeNotification:FBSimulatorNotificationNameSimulatorApplicationDidTerminate userInfo:@{
    FBSimulatorNotificationUserInfoKeyExpectedTermination : @(expected),
    FBSimulatorNotificationUserInfoKeyProcess : applicationProcess
  }];
}

- (void)connectionDidConnect:(FBSimulatorConnection *)connection
{
  [self materializeNotification:FBSimulatorNotificationNameConnectionDidConnect userInfo:@{
    FBSimulatorNotificationUserInfoKeyConnection : connection,
  }];
}

- (void)connectionDidDisconnect:(FBSimulatorConnection *)connection expected:(BOOL)expected
{
  [self materializeNotification:FBSimulatorNotificationNameConnectionDidDisconnect userInfo:@{
    FBSimulatorNotificationUserInfoKeyExpectedTermination : @(expected),
    FBSimulatorNotificationUserInfoKeyConnection : connection,
  }];
}

- (void)simulatorDidLaunch:(FBProcessInfo *)launchdProcess
{
  [self materializeNotification:FBSimulatorNotificationNameDidLaunch userInfo:@{
    FBSimulatorNotificationUserInfoKeyProcess : launchdProcess
  }];
}

- (void)simulatorDidTerminate:(FBProcessInfo *)launchdProcess expected:(BOOL)expected
{
  [self materializeNotification:FBSimulatorNotificationNameDidTerminate userInfo:@{
    FBSimulatorNotificationUserInfoKeyExpectedTermination : @(expected),
    FBSimulatorNotificationUserInfoKeyProcess : launchdProcess
  }];
}

- (void)agentDidLaunch:(FBAgentLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)agentProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  [self materializeNotification:FBSimulatorNotificationNameAgentProcessDidLaunch userInfo:@{
    FBSimulatorNotificationUserInfoKeyProcess : agentProcess
  }];
}

- (void)agentDidTerminate:(FBProcessInfo *)agentProcess expected:(BOOL)expected
{
  [self materializeNotification:FBSimulatorNotificationNameAgentProcessDidTerminate userInfo:@{
    FBSimulatorNotificationUserInfoKeyExpectedTermination : @(expected),
    FBSimulatorNotificationUserInfoKeyProcess : agentProcess
  }];
}

- (void)applicationDidLaunch:(FBApplicationLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)applicationProcess
{
  [self materializeNotification:FBSimulatorNotificationNameApplicationProcessDidLaunch userInfo:@{
    FBSimulatorNotificationUserInfoKeyProcess : applicationProcess,
    FBSimulatorNotificationUserInfoKeyWaitingForDebugger : @(launchConfig.waitForDebugger),
  }];
}

- (void)applicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{
  [self materializeNotification:FBSimulatorNotificationNameApplicationProcessDidTerminate userInfo:@{
    FBSimulatorNotificationUserInfoKeyExpectedTermination : @(expected),
    FBSimulatorNotificationUserInfoKeyProcess : applicationProcess
  }];
}

- (void)testmanagerDidConnect:(FBTestManager *)testManager
{
  [self materializeNotification:FBSimulatorNotificationNameTestManagerDidConnect userInfo:@{
    FBSimulatorNotificationUserInfoKeyTestManager : testManager
  }];
}

- (void)testmanagerDidDisconnect:(FBTestManager *)testManager
{
  [self materializeNotification:FBSimulatorNotificationNameTestManagerDidDisconnect userInfo:@{
    FBSimulatorNotificationUserInfoKeyTestManager : testManager
  }];
}

- (void)diagnosticAvailable:(FBDiagnostic *)diagnostic
{
  [self materializeNotification:FBSimulatorNotificationNameGainedDiagnosticInformation userInfo:@{
    FBSimulatorNotificationUserInfoKeyDiagnostic : diagnostic
  }];
}

- (void)didChangeState:(FBSimulatorState)state
{
  [self materializeNotification:FBSimulatorNotificationNameStateDidChange userInfo:@{
    FBSimulatorNotificationUserInfoKeyState : @(state)
  }];
}

- (void)terminationHandleAvailable:(id<FBTerminationHandle>)terminationHandle
{

}

#pragma mark Private

- (void)materializeNotification:(FBSimulatorNotificationName)notificationName userInfo:(NSDictionary *)userInfo
{
  NSParameterAssert(notificationName);
  NSParameterAssert(userInfo);

  [NSNotificationCenter.defaultCenter postNotificationName:notificationName object:self.simulator userInfo:userInfo];
}

@end
