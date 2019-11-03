/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorNotificationEventSink.h"

#import "FBSimulatorApplicationOperation.h"
#import "FBSimulatorAgentOperation.h"

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
FBSimulatorNotificationName const FBSimulatorNotificationNameStateDidChange = @"FBSimulatorNotificationNameStateDidChange";

NSString *const FBSimulatorNotificationUserInfoKeyExpectedTermination = @"expected";
NSString *const FBSimulatorNotificationUserInfoKeyProcess = @"process";
NSString *const FBSimulatorNotificationUserInfoKeyProcessIdentifier = @"pid";
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

- (void)agentDidLaunch:(FBSimulatorAgentOperation *)operation
{
  [self materializeNotification:FBSimulatorNotificationNameAgentProcessDidLaunch userInfo:@{
    FBSimulatorNotificationUserInfoKeyProcessIdentifier : @(operation.processIdentifier),
  }];
}

- (void)agentDidTerminate:(FBSimulatorAgentOperation *)operation statLoc:(int)statLoc
{
  [self materializeNotification:FBSimulatorNotificationNameAgentProcessDidTerminate userInfo:@{
    FBSimulatorNotificationUserInfoKeyExpectedTermination : @([FBSimulatorAgentOperation isExpectedTerminationForStatLoc:statLoc]),
    FBSimulatorNotificationUserInfoKeyProcessIdentifier : @(operation.processIdentifier),
  }];
}

- (void)applicationDidLaunch:(FBSimulatorApplicationOperation *)operation
{
  [self materializeNotification:FBSimulatorNotificationNameApplicationProcessDidLaunch userInfo:@{
    FBSimulatorNotificationUserInfoKeyProcessIdentifier : @(operation.processIdentifier),
    FBSimulatorNotificationUserInfoKeyWaitingForDebugger : @(operation.configuration.waitForDebugger),
  }];
}

- (void)applicationDidTerminate:(FBSimulatorApplicationOperation *)operation expected:(BOOL)expected
{
  [self materializeNotification:FBSimulatorNotificationNameApplicationProcessDidTerminate userInfo:@{
    FBSimulatorNotificationUserInfoKeyExpectedTermination : @(expected),
    FBSimulatorNotificationUserInfoKeyProcessIdentifier : @(operation.processIdentifier),
  }];
}

- (void)didChangeState:(FBiOSTargetState)state
{
  [self materializeNotification:FBSimulatorNotificationNameStateDidChange userInfo:@{
    FBSimulatorNotificationUserInfoKeyState : @(state)
  }];
}

#pragma mark Private

- (void)materializeNotification:(FBSimulatorNotificationName)notificationName userInfo:(NSDictionary *)userInfo
{
  NSParameterAssert(notificationName);
  NSParameterAssert(userInfo);

  [NSNotificationCenter.defaultCenter postNotificationName:notificationName object:self.simulator userInfo:userInfo];
}

@end
