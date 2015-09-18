/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorSessionStateGenerator.h"

#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorProcess+Private.h"
#import "FBSimulatorSessionState+Private.h"
#import "FBSimulatorSessionState+Queries.h"

@interface FBSimulatorSessionStateGenerator ()

@property (nonatomic, strong) FBSimulatorSessionState *state;

@end

@implementation FBSimulatorSessionStateGenerator

+ (instancetype)generatorWithSession:(FBSimulatorSession *)session
{
  FBSimulatorSessionState *state = [FBSimulatorSessionState new];
  state.session = session;
  state.lifecycle = FBSimulatorSessionLifecycleStateNotStarted;
  state.runningProcessesSet = [NSMutableOrderedSet new];
  state.previousState = nil;
  state.timestamp = [NSDate date];
  state.simulatorState = state.simulator.state;

  FBSimulatorSessionStateGenerator *generator = [self new];
  generator.state = state;
  return generator;
}

- (instancetype)updateLifecycle:(FBSimulatorSessionLifecycleState)lifecycle
{
  return [self updateCurrentState:^ FBSimulatorSessionState * (FBSimulatorSessionState *state) {
    state.lifecycle = lifecycle;
    return state;
  }];
}

- (instancetype)updateSimulatorState:(FBSimulatorState)simulatorState
{
  return [self updateCurrentState:^FBSimulatorSessionState *(FBSimulatorSessionState *state) {
    state.simulatorState = simulatorState;
    return state;
  }];
}

- (instancetype)update:(FBProcessLaunchConfiguration *)launchConfig withProcessIdentifier:(NSInteger)processIdentifier
{
  return [self updateCurrentState:^ FBSimulatorSessionState * (FBSimulatorSessionState *state) {
    NSCParameterAssert(state.lifecycle != FBSimulatorSessionLifecycleStateNotStarted);
    NSCParameterAssert([state processForLaunchConfiguration:launchConfig] == nil);

    FBUserLaunchedProcess *processState = [FBUserLaunchedProcess new];
    processState.processIdentifier = processIdentifier;
    processState.launchConfiguration = launchConfig;
    processState.launchDate = [NSDate date];
    processState.diagnostics = @{};

    NSMutableOrderedSet *runningProcessesSet = state.runningProcessesSet;
    [runningProcessesSet insertObject:processState atIndex:0];
    state.runningProcessesSet = runningProcessesSet;
    return state;
  }];
}

- (instancetype)update:(FBSimulatorApplication *)application withDiagnosticNamed:(NSString *)diagnosticName data:(id)data
{
  NSPredicate *predicate = [NSPredicate predicateWithBlock:^ BOOL (FBSimulatorSessionState *sessionState, NSDictionary *bindings) {
    return [sessionState processForApplication:application] != nil;
  }];

  return [self amendPriorState:predicate update:^ FBSimulatorSessionState * (FBSimulatorSessionState *sessionState) {
    FBUserLaunchedProcess *currentProcessState = [sessionState processForApplication:application];
    NSCAssert(currentProcessState, @"Can't get current process state");

    FBUserLaunchedProcess *nextProcessState = [self.class
      updateProcessState:currentProcessState
      withBlock:^ FBUserLaunchedProcess * (FBUserLaunchedProcess *processState) {
        NSMutableDictionary *diagnostics = [processState.diagnostics mutableCopy];
        diagnostics[diagnosticName] = data;
        processState.diagnostics = diagnostics;
        return processState;
    }];

    NSInteger indexOfState = [sessionState.runningProcessesSet indexOfObject:currentProcessState];
    NSCAssert(indexOfState != NSNotFound, @"Whar did this come from then");
    [sessionState.runningProcessesSet replaceObjectAtIndex:indexOfState withObject:nextProcessState];
    return sessionState;
  }];
}

- (instancetype)remove:(FBSimulatorBinary *)binary;
{
  return [self updateCurrentState:^ FBSimulatorSessionState * (FBSimulatorSessionState *sessionState) {
    NSCParameterAssert(sessionState.lifecycle != FBSimulatorSessionLifecycleStateNotStarted);
    FBUserLaunchedProcess *processState = [sessionState processForBinary:binary];
    NSCParameterAssert(processState);

    NSMutableOrderedSet *runningProcessesSet = sessionState.runningProcessesSet;
    [runningProcessesSet removeObject:processState];
    sessionState.runningProcessesSet = runningProcessesSet;
    return sessionState;
  }];
}

- (FBSimulatorSessionState *)currentState
{
  return self.state;
}

#pragma mark Private

- (instancetype)updateCurrentState:( FBSimulatorSessionState *(^)(FBSimulatorSessionState *state) )block
{
  self.state = [self.class updateState:self.currentState addNewLink:YES withBlock:block];
  return self;
}

- (instancetype)amendPriorState:(NSPredicate *)predicate update:( FBSimulatorSessionState *(^)(FBSimulatorSessionState *sessionState) )block
{
  self.state = [self.class updateState:self.currentState addNewLink:NO withBlock:^ FBSimulatorSessionState * (FBSimulatorSessionState *sessionState) {
    FBSimulatorSessionState *currentState = sessionState;
    FBSimulatorSessionState *parentState = nil;
    while (true) {
      if ([predicate evaluateWithObject:currentState]) {
        break;
      }
      parentState = sessionState;
      currentState = sessionState.previousState;
      if (!sessionState) {
        return nil;
      }
    }

    FBSimulatorSessionState *nextState = [self.class updateState:currentState addNewLink:NO withBlock:block];
    if (parentState) {
      parentState.previousState = nextState;
      return sessionState;
    }
    return nextState;
  }];
  return self;
}

+ (FBSimulatorSessionState *)updateState:(FBSimulatorSessionState *)sessionState addNewLink:(BOOL)addNewLink withBlock:( FBSimulatorSessionState *(^)(FBSimulatorSessionState *state) )block
{
  NSParameterAssert(sessionState);
  NSParameterAssert(block);

  FBSimulatorSessionState *nextSessionState = block([sessionState copy]);
  if (!nextSessionState) {
    return sessionState;
  }
  if ([nextSessionState isEqual:sessionState]) {
    return sessionState;
  }
  if (addNewLink) {
    nextSessionState.timestamp = [NSDate date];
    nextSessionState.previousState = sessionState;
  }
  return nextSessionState;
}

+ (FBUserLaunchedProcess *)updateProcessState:(FBUserLaunchedProcess *)processState withBlock:( FBUserLaunchedProcess *(^)(FBUserLaunchedProcess *processState) )block
{
  FBUserLaunchedProcess *nextProcessState = block([processState copy]);
  if (!nextProcessState) {
    return processState;
  }
  if ([nextProcessState isEqual:processState]) {
    return processState;
  }
  return nextProcessState;
}

@end
