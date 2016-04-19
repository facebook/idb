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
@property (nonatomic, copy, readonly) NSString *persistencePath;

@end

@implementation FBSimulatorHistoryGenerator

@synthesize peristenceEnabled = _peristenceEnabled;
@synthesize history = _history;

#pragma mark Initializers

+ (instancetype)forSimulator:(FBSimulator *)simulator
{
  return [[FBSimulatorHistoryGenerator new] initWithHistory:[self fetchHistoryForSimulator:simulator] persistencePath:[self pathForPerisistantHistory:simulator]];
}

- (instancetype)initWithHistory:(FBSimulatorHistory *)history persistencePath:(NSString *)persistencePath
{
  NSParameterAssert(history);
  NSParameterAssert(persistencePath);

  self = [super init];
  if (!self) {
    return nil;
  }

  _history = history;
  _persistencePath = persistencePath;

  return self;
}

#pragma mark Accessors

- (BOOL)isPeristenceEnabled
{
  return _peristenceEnabled;
}

- (void)setPeristenceEnabled:(BOOL)peristenceEnabled
{
  if (peristenceEnabled == NO) {
    [self removePersistentHistory];
  }
  _peristenceEnabled = peristenceEnabled;
}

- (FBSimulatorHistory *)history
{
  return _history;
}

- (void)setHistory:(FBSimulatorHistory *)history
{
  if (![history isEqual:_history]) {
    [self persist];
  }
  _history = history;
}

#pragma mark Public

- (FBSimulatorHistory *)currentState
{
  return self.history;
}

#pragma mark Persistence

- (void)removePersistentHistory
{
  [NSFileManager.defaultManager removeItemAtPath:self.persistencePath error:nil];
}

+ (NSString *)pathForPerisistantHistory:(FBSimulator *)simulator
{
  return [simulator.auxillaryDirectory stringByAppendingPathExtension:@"history"];
}

+ (FBSimulatorHistory *)freshHistoryForSimulator:(FBSimulator *)simulator
{
  FBSimulatorHistory *history = [FBSimulatorHistory new];
  history.simulatorState = simulator.state;
  return history;
}

+ (FBSimulatorHistory *)fetchHistoryForSimulator:(FBSimulator *)simulator
{
  return [NSKeyedUnarchiver unarchiveObjectWithFile:[self pathForPerisistantHistory:simulator]]
      ?: [self freshHistoryForSimulator:simulator];
}

- (BOOL)persist
{
  if (!self.isPersistenceEnabled) {
    return YES;
  }
  return [NSKeyedArchiver archiveRootObject:self.history toFile:self.persistencePath];
}

#pragma mark FBSimulatorEventSink Implementation

- (void)containerApplicationDidLaunch:(FBProcessInfo *)applicationProcess
{
}

- (void)containerApplicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{
}

- (void)bridgeDidConnect:(FBSimulatorBridge *)bridge
{
}

- (void)bridgeDidDisconnect:(FBSimulatorBridge *)bridge expected:(BOOL)expected
{

}

- (void)simulatorDidLaunch:(FBProcessInfo *)launchdSimProcess
{
}

- (void)simulatorDidTerminate:(FBProcessInfo *)launchdSimProcess expected:(BOOL)expected
{
}

- (void)agentDidLaunch:(FBAgentLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)agentProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  [self processLaunched:agentProcess withConfiguration:launchConfig];
}

- (void)agentDidTerminate:(FBProcessInfo *)agentProcess expected:(BOOL)expected
{
  [self processTerminated:agentProcess];
  [self updateProcess:agentProcess withMetadataNamed:FBSimulatorHistoryDiagnosticNameTerminationStatus value:@(expected)];
}

- (void)testmanagerDidConnect:(FBTestManager *)testManager
{
}

- (void)testmanagerDidDisconnect:(FBTestManager *)testManager
{
}

- (void)applicationDidLaunch:(FBApplicationLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)applicationProcess
{
  [self processLaunched:applicationProcess withConfiguration:launchConfig];
}

- (void)applicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{
  [self processTerminated:applicationProcess];
  [self updateProcess:applicationProcess withMetadataNamed:FBSimulatorHistoryDiagnosticNameTerminationStatus value:@(expected)];
}

- (void)diagnosticAvailable:(FBDiagnostic *)diagnostic
{

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

- (instancetype)updateProcess:(FBProcessInfo *)process withMetadataNamed:(NSString *)diagnosticName value:(id<NSCopying, NSCoding>)value
{
  return [self updateCurrentState:^ FBSimulatorHistory * (FBSimulatorHistory *history) {
    NSMutableDictionary *metadata = [history.mutableProcessMetadata[process] mutableCopy] ?: [NSMutableDictionary dictionary];
    metadata[diagnosticName] = value;
    history.mutableProcessMetadata[process] = metadata;
    return history;
  }];
}

#pragma mark Private

- (instancetype)updateCurrentState:( FBSimulatorHistory *(^)(FBSimulatorHistory *history) )block
{
  self.history = [self.class updateState:self.currentState withBlock:block];
  return self;
}

+ (FBSimulatorHistory *)updateState:(FBSimulatorHistory *)history withBlock:( FBSimulatorHistory *(^)(FBSimulatorHistory *history) )block
{
  NSParameterAssert(history);
  NSParameterAssert(block);

  FBSimulatorHistory *nextHistory = block([history copy]);
  if (!nextHistory) {
    return history;
  }
  if ([nextHistory isEqual:history]) {
    return history;
  }
  nextHistory.timestamp = [NSDate date];
  nextHistory.previousState = history;
  return nextHistory;
}

@end
