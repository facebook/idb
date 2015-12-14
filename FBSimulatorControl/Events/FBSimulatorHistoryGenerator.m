/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorHistoryGenerator.h"

#import "FBProcessLaunchConfiguration.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorHistory+Private.h"
#import "FBSimulatorHistory+Queries.h"

@interface FBSimulatorHistoryGenerator ()

@property (nonatomic, strong, readwrite) FBSimulatorHistory *history;

@end

@implementation FBSimulatorHistoryGenerator

+ (instancetype)withSimulator:(FBSimulator *)simulator;
{
  FBSimulatorHistory *history = [FBSimulatorHistory new];
  history.simulatorState = simulator.state;

  return [[FBSimulatorHistoryGenerator new] initWithHistory:history];
}

- (instancetype)initWithHistory:(FBSimulatorHistory *)history
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _history = history;

  return self;
}

- (FBSimulatorHistory *)currentState
{
  return self.history;
}

#pragma mark FBSimulatorEventSink Implementation

- (void)didStartWithLaunchInfo:(FBSimulatorLaunchInfo *)launchInfo
{

}

- (void)didTerminate:(BOOL)expected
{

}

- (void)agentDidLaunch:(FBAgentLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)agentProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  [self processLaunched:agentProcess withConfiguration:launchConfig];
}

- (void)agentDidTerminate:(FBProcessInfo *)agentProcess expected:(BOOL)expected
{
  [self processTerminated:agentProcess];
}

- (void)applicationDidLaunch:(FBApplicationLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)applicationProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  [self processLaunched:applicationProcess withConfiguration:launchConfig];
}

- (void)applicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{
  [self processTerminated:applicationProcess];
}

- (void)diagnosticInformationAvailable:(NSString *)name process:(FBProcessInfo *)process value:(id<NSCopying, NSCoding>)value
{
  if (!process) {
    [self updateWithSimulatorDiagnosticNamed:name value:value];
    return;
  }
  [self update:process withProcessDiagnosticNamed:name value:value];
}

- (void)didChangeState:(FBSimulatorState)state
{
  [self updateSimulatorState:state];
}

- (void)terminationHandleAvailable:(id<FBTerminationHandle>)terminationHandle
{

}

#pragma mark Mutation

- (instancetype)updateSimulatorState:(FBSimulatorState)simulatorState
{
  return [self updateCurrentState:^ FBSimulatorHistory * (FBSimulatorHistory *history) {
    history.simulatorState = simulatorState;
    return history;
  }];
}

- (instancetype)processLaunched:(FBProcessInfo *)processInfo withConfiguration:(FBProcessLaunchConfiguration *)configuration
{
  return [self updateCurrentState:^ FBSimulatorHistory * (FBSimulatorHistory *history) {
    [history.mutableLaunchedProcesses insertObject:processInfo atIndex:0];
    history.mutableProcessLaunchConfigurations[processInfo] = configuration;
    return history;
  }];
}

- (instancetype)processTerminated:(FBProcessInfo *)processInfo
{
  return [self updateCurrentState:^ FBSimulatorHistory * (FBSimulatorHistory *history) {
    [history.mutableLaunchedProcesses removeObject:processInfo];
    return history;
  }];
}

- (instancetype)update:(FBProcessInfo *)process withProcessDiagnosticNamed:(NSString *)diagnosticName value:(id<NSCopying, NSCoding>)value
{
  return [self updateCurrentState:^ FBSimulatorHistory * (FBSimulatorHistory *history) {
    NSMutableDictionary *processDiagnostics = [history.mutableProcessDiagnostics[process] mutableCopy] ?: [NSMutableDictionary dictionary];
    processDiagnostics[diagnosticName] = value;
    history.mutableProcessDiagnostics[process] = processDiagnostics;
    return history;
  }];
}

- (instancetype)updateWithSimulatorDiagnosticNamed:(NSString *)diagnostic value:(id<NSCopying, NSCoding>)value
{
  return [self updateCurrentState:^ FBSimulatorHistory * (FBSimulatorHistory *history) {
    history.mutableSimulatorDiagnostics[diagnostic] = value;
    return history;
  }];
}

#pragma mark Private

- (instancetype)updateCurrentState:( FBSimulatorHistory *(^)(FBSimulatorHistory *history) )block
{
  self.history = [self.class updateState:self.currentState withBlock:block];
  return self;
}

+ (FBSimulatorHistory *)updateState:(FBSimulatorHistory *)sessionState withBlock:( FBSimulatorHistory *(^)(FBSimulatorHistory *history) )block
{
  NSParameterAssert(sessionState);
  NSParameterAssert(block);

  FBSimulatorHistory *nextSessionState = block([sessionState copy]);
  if (!nextSessionState) {
    return sessionState;
  }
  if ([nextSessionState isEqual:sessionState]) {
    return sessionState;
  }
  nextSessionState.timestamp = [NSDate date];
  nextSessionState.previousState = sessionState;
  return nextSessionState;
}

+ (FBProcessInfo *)updateProcessState:(FBProcessInfo *)processState withBlock:( FBProcessInfo *(^)(FBProcessInfo *processState) )block
{
  FBProcessInfo *nextProcessState = block([processState copy]);
  if (!nextProcessState) {
    return processState;
  }
  if ([nextProcessState isEqual:processState]) {
    return processState;
  }
  return nextProcessState;
}

@end
