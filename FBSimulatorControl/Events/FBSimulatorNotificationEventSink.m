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

NSString *const FBSimulatorExpectedTerminationKey = @"expected";
NSString *const FBSimulatorProcessKey = @"process";
NSString *const FBSimulatorDiagnosticLog = @"diagnostic_log";
NSString *const FBSimulatorConnectionKey = @"connection";
NSString *const FBSimulatorStateKey = @"simulator_state";
NSString *const FBSimulatorTestManagerKey = @"testManager";

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
    FBSimulatorProcessKey : applicationProcess
  }];
}

- (void)containerApplicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{
  [self materializeNotification:FBSimulatorNotificationNameSimulatorApplicationDidTerminate userInfo:@{
    FBSimulatorExpectedTerminationKey : @(expected),
    FBSimulatorProcessKey : applicationProcess
  }];
}

- (void)connectionDidConnect:(FBSimulatorConnection *)connection
{
  [self materializeNotification:FBSimulatorNotificationNameConnectionDidConnect userInfo:@{
    FBSimulatorConnectionKey : connection,
  }];
}

- (void)connectionDidDisconnect:(FBSimulatorConnection *)connection expected:(BOOL)expected
{
  [self materializeNotification:FBSimulatorNotificationNameConnectionDidDisconnect userInfo:@{
    FBSimulatorExpectedTerminationKey : @(expected),
    FBSimulatorConnectionKey : connection,
  }];
}

- (void)simulatorDidLaunch:(FBProcessInfo *)launchdProcess
{
  [self materializeNotification:FBSimulatorNotificationNameDidLaunch userInfo:@{
    FBSimulatorProcessKey : launchdProcess
  }];
}

- (void)simulatorDidTerminate:(FBProcessInfo *)launchdProcess expected:(BOOL)expected
{
  [self materializeNotification:FBSimulatorNotificationNameDidTerminate userInfo:@{
    FBSimulatorExpectedTerminationKey : @(expected),
    FBSimulatorProcessKey : launchdProcess
  }];
}

- (void)agentDidLaunch:(FBAgentLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)agentProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  [self materializeNotification:FBSimulatorNotificationNameAgentProcessDidLaunch userInfo:@{
    FBSimulatorProcessKey : agentProcess
  }];
}

- (void)agentDidTerminate:(FBProcessInfo *)agentProcess expected:(BOOL)expected
{
  [self materializeNotification:FBSimulatorNotificationNameAgentProcessDidTerminate userInfo:@{
    FBSimulatorExpectedTerminationKey : @(expected),
    FBSimulatorProcessKey : agentProcess
  }];
}

- (void)applicationDidLaunch:(FBApplicationLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)applicationProcess
{
  [self materializeNotification:FBSimulatorNotificationNameApplicationProcessDidLaunch userInfo:@{
    FBSimulatorProcessKey : applicationProcess,
  }];
}

- (void)applicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{
  [self materializeNotification:FBSimulatorNotificationNameApplicationProcessDidTerminate userInfo:@{
    FBSimulatorExpectedTerminationKey : @(expected),
    FBSimulatorProcessKey : applicationProcess
  }];
}

- (void)testmanagerDidConnect:(FBTestManager *)testManager
{
  [self materializeNotification:FBSimulatorNotificationNameTestManagerDidConnect userInfo:@{
    FBSimulatorTestManagerKey : testManager
  }];
}

- (void)testmanagerDidDisconnect:(FBTestManager *)testManager
{
  [self materializeNotification:FBSimulatorNotificationNameTestManagerDidDisconnect userInfo:@{
    FBSimulatorTestManagerKey : testManager
  }];
}

- (void)diagnosticAvailable:(FBDiagnostic *)diagnostic
{
  [self materializeNotification:FBSimulatorNotificationNameGainedDiagnosticInformation userInfo:@{
    FBSimulatorDiagnosticLog : diagnostic
  }];
}

- (void)didChangeState:(FBSimulatorState)state
{
  [self materializeNotification:FBSimulatorNotificationNameStateDidChange userInfo:@{
    FBSimulatorStateKey : @(state)
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
