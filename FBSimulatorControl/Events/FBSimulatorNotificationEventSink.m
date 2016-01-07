/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorNotificationEventSink.h"

NSString *const FBSimulatorContainerDidLaunchNotification = @"FBSimulatorContainerDidLaunchNotification";
NSString *const FBSimulatorContainerDidTerminateNotification = @"FBSimulatorContainerDidTerminateNotification";
NSString *const FBSimulatorApplicationProcessDidLaunchNotification = @"FBSimulatorApplicationProcessDidLaunchNotification";
NSString *const FBSimulatorApplicationProcessDidTerminateNotification = @"FBSimulatorApplicationProcessDidTerminateNotification";
NSString *const FBSimulatorAgentProcessDidLaunchNotification = @"FBSimulatorAgentProcessDidLaunchNotification";
NSString *const FBSimulatorAgentProcessDidTerminateNotification = @"FBSimulatorAgentProcessDidTerminateNotification";
NSString *const FBSimulatorGainedDiagnosticInformation = @"FBSimulatorGainedDiagnosticInformation";
NSString *const FBSimulatorStateDidChange = @"FBSimulatorStateDidChange";
NSString *const FBSimulatorExpectedTerminationKey = @"expected";
NSString *const FBSimulatorProcessKey = @"process";
NSString *const FBSimulatorDiagnosticName = @"diagnostic_name";
NSString *const FBSimulatorDiagnosticValue = @"diagnostic_value";
NSString *const FBSimulatorStateKey = @"simulator_state";

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

- (void)containerApplicationDidLaunch:(FBSimulatorLaunchInfo *)launchInfo
{
  [self materializeNotification:FBSimulatorContainerDidLaunchNotification userInfo:@{}];
}

- (void)containerApplicationDidTerminate:(FBSimulatorLaunchInfo *)launchInfo expected:(BOOL)expected
{
  [self materializeNotification:FBSimulatorContainerDidTerminateNotification userInfo:@{ FBSimulatorExpectedTerminationKey : @(expected) }];
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

- (void)applicationDidLaunch:(FBApplicationLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)applicationProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
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

- (void)diagnosticInformationAvailable:(NSString *)name process:(FBProcessInfo *)process value:(id<NSCopying, NSCoding>)value
{
  NSMutableDictionary *userInfo = [@{
    FBSimulatorDiagnosticName : name,
    FBSimulatorDiagnosticValue : value
  } mutableCopy];
  if (process) {
    userInfo[FBSimulatorProcessKey] = process;
  }

  [self materializeNotification:FBSimulatorGainedDiagnosticInformation userInfo:userInfo];
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
