/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorSessionLifecycle.h"

#import "FBCoreSimulatorNotifier.h"
#import "FBDispatchSourceNotifier.h"
#import "FBProcessLaunchConfiguration.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorSession.h"
#import "FBSimulatorSessionState+Private.h"
#import "FBSimulatorSessionState.h"
#import "FBSimulatorSessionStateGenerator.h"

NSString *const FBSimulatorSessionDidStartNotification = @"FBSimulatorSessionDidStartNotification";
NSString *const FBSimulatorSessionDidEndNotification = @"FBSimulatorSessionDidEndNotification";
NSString *const FBSimulatorSessionSimulatorProcessDidLaunchNotification = @"FBSimulatorSessionSimulatorProcessDidLaunchNotification";
NSString *const FBSimulatorSessionSimulatorProcessDidTerminateNotification = @"FBSimulatorSessionSimulatorProcessDidTerminateNotification";
NSString *const FBSimulatorSessionApplicationProcessDidLaunchNotification = @"FBSimulatorSessionApplicationProcessDidLaunchNotification";
NSString *const FBSimulatorSessionApplicationProcessDidTerminateNotification = @"FBSimulatorSessionApplicationProcessDidTerminateNotification";
NSString *const FBSimulatorSessionAgentProcessDidLaunchNotification = @"FBSimulatorSessionAgentProcessDidLaunchNotification";
NSString *const FBSimulatorSessionAgentProcessDidTerminateNotification = @"FBSimulatorSessionAgentProcessDidTerminateNotification";
NSString *const FBSimulatorSessionStateKey = @"state";
NSString *const FBSimulatorSessionSubjectKey = @"subject";
NSString *const FBSimulatorSessionExpectedKey = @"expected";

@interface FBSimulatorSessionLifecycle ()

@property (nonatomic, weak, readwrite) FBSimulatorSession *session;
@property (nonatomic, strong, readwrite) FBSimulatorSessionStateGenerator *generator;

@property (nonatomic, strong, readwrite) id<FBTerminationHandle> simulatorTerminationHandle;
@property (nonatomic, strong, readwrite) NSMutableDictionary *notifiers;
@property (nonatomic, strong, readwrite) NSMutableDictionary *fileHandles;
@property (nonatomic, strong, readwrite) NSMutableArray *terminationHandlers;

@end

@implementation FBSimulatorSessionLifecycle

#pragma mark - Initializers

+ (instancetype)lifecycleWithSession:(FBSimulatorSession *)session;
{
  return [[FBSimulatorSessionLifecycle alloc] initWithSession:session];
}

- (instancetype)initWithSession:(FBSimulatorSession *)session
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _session = session;
  _generator = [FBSimulatorSessionStateGenerator generatorWithSession:session];
  _notifiers = [NSMutableDictionary dictionary];
  _terminationHandlers = [NSMutableArray array];
  _fileHandles = [NSMutableDictionary dictionary];
  return self;
}

#pragma mark Simulator

- (void)simulatorWillStart:(FBSimulator *)simulator
{
  NSParameterAssert(simulator);
  [self registerSimDeviceNotifier:simulator];
}

- (void)simulator:(FBSimulator *)simulator didStartWithProcessIdentifier:(NSInteger)processIdentifier terminationHandle:(id<FBTerminationHandle>)terminationHandle
{
  NSParameterAssert(terminationHandle);
  NSParameterAssert(self.simulatorTerminationHandle == nil);
  NSParameterAssert(simulator == self.session.simulator);

  if (self.currentState.lifecycle == FBSimulatorSessionLifecycleStateNotStarted) {
    [self didStartSession];
  }

  simulator.processIdentifier = processIdentifier;
  self.simulatorTerminationHandle = terminationHandle;
  [self createNotifierForBinary:simulator.simulatorApplication.binary onProcessIdentifier:processIdentifier withHandler:^(FBSimulatorSessionLifecycle *lifecycle) {
    [lifecycle simulatorDidUnexpectedlyTerminate:simulator];
  }];

  [self materializeNotification:FBSimulatorSessionSimulatorProcessDidLaunchNotification withSubject:simulator];
}

- (void)simulatorWillTerminate:(FBSimulator *)simulator
{
  // If the termination is expected, i.e. initiated the termination handler must have been called.
  [self clearSimulatorState:simulator];
}

- (void)simulatorDidUnexpectedlyTerminate:(FBSimulator *)simulator
{
  // If there's an unexpected termination, we should still clean up
  [self.simulatorTerminationHandle terminate];
  [self clearSimulatorState:simulator];
}

- (void)clearSimulatorState:(FBSimulator *)simulator
{
  NSParameterAssert(simulator == self.session.simulator);
  NSParameterAssert(self.currentState.lifecycle == FBSimulatorSessionLifecycleStateStarted);

  self.simulatorTerminationHandle = nil;
  simulator.processIdentifier = -1;
  [self unregisterNotifierForBinary:simulator.simulatorApplication.binary];
  [self materializeNotification:FBSimulatorSessionSimulatorProcessDidTerminateNotification withSubject:simulator];
}

#pragma mark Agent

- (void)agentDidLaunch:(FBAgentLaunchConfiguration *)launchConfig didStartWithProcessIdentifier:(NSInteger)processIdentifier stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  NSParameterAssert(launchConfig);
  NSParameterAssert(processIdentifier > 0);
  NSParameterAssert(self.currentState.lifecycle == FBSimulatorSessionLifecycleStateStarted);

  [self.generator update:launchConfig withProcessIdentifier:processIdentifier];
  [self registerFileHandle:stdOut forBinary:launchConfig.agentBinary];
  [self registerFileHandle:stdErr forBinary:launchConfig.agentBinary];
  [self createNotifierForBinary:launchConfig.agentBinary onProcessIdentifier:processIdentifier withHandler:^(FBSimulatorSessionLifecycle *lifecycle) {
    [lifecycle agentDidUnexpectedlyTerminate:launchConfig.agentBinary];
  }];

  [self materializeNotification:FBSimulatorSessionAgentProcessDidLaunchNotification withSubject:launchConfig expected:YES];
}

- (void)agentWillTerminate:(FBSimulatorBinary *)agentBinary
{
  [self clearAgentState:agentBinary];
  [self materializeNotification:FBSimulatorSessionAgentProcessDidTerminateNotification withSubject:agentBinary expected:YES];
}

- (void)agentDidUnexpectedlyTerminate:(FBSimulatorBinary *)agentBinary
{
  [self clearAgentState:agentBinary];
  [self materializeNotification:FBSimulatorSessionAgentProcessDidTerminateNotification withSubject:agentBinary expected:NO];
}

- (void)clearAgentState:(FBSimulatorBinary *)agentBinary
{
  NSParameterAssert(agentBinary);
  NSParameterAssert(self.currentState.lifecycle == FBSimulatorSessionLifecycleStateStarted);

  [self unregisterNotifierForBinary:agentBinary];
  [self unregisterFileHandlesForBinary:agentBinary];
  [self.generator remove:agentBinary];
}

#pragma mark Application

- (void)applicationDidLaunch:(FBApplicationLaunchConfiguration *)launchConfig didStartWithProcessIdentifier:(NSInteger)processIdentifier stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  NSParameterAssert(launchConfig);
  NSParameterAssert(processIdentifier > 0);
  NSParameterAssert(self.currentState.lifecycle == FBSimulatorSessionLifecycleStateStarted);

  [self.generator update:launchConfig withProcessIdentifier:processIdentifier];
  [self registerFileHandle:stdOut forBinary:launchConfig.application.binary];
  [self registerFileHandle:stdErr forBinary:launchConfig.application.binary];
  [self createNotifierForBinary:launchConfig.application.binary onProcessIdentifier:processIdentifier withHandler:^(FBSimulatorSessionLifecycle *lifecycle) {
    [lifecycle applicationDidUnexpectedlyTerminate:launchConfig.application];
  }];

  [self materializeNotification:FBSimulatorSessionApplicationProcessDidLaunchNotification withSubject:launchConfig];
}

- (void)applicationWillTerminate:(FBSimulatorApplication *)application
{
  [self clearApplicationState:application];
  [self materializeNotification:FBSimulatorSessionApplicationProcessDidTerminateNotification withSubject:application expected:YES];
}

- (void)applicationDidUnexpectedlyTerminate:(FBSimulatorApplication *)application
{
  [self clearApplicationState:application];
  [self materializeNotification:FBSimulatorSessionApplicationProcessDidTerminateNotification withSubject:application expected:NO];
}

- (void)clearApplicationState:(FBSimulatorApplication *)application
{
  NSParameterAssert(application);
  NSParameterAssert(self.currentState.lifecycle == FBSimulatorSessionLifecycleStateStarted);

  [self unregisterNotifierForBinary:application.binary];
  [self unregisterFileHandlesForBinary:application.binary];
  [self.generator remove:application.binary];
}

- (void)application:(FBSimulatorApplication *)application didGainDiagnosticInformationWithName:(NSString *)diagnosticName data:(id)data
{
  NSParameterAssert(diagnosticName);
  NSParameterAssert(data);

  [self.generator update:application withDiagnosticNamed:diagnosticName data:data];
}

#pragma mark Cleanup

- (void)associateEndOfSessionCleanup:(id<FBTerminationHandle>)terminationHandle
{
  [self.terminationHandlers addObject:terminationHandle];
}

#pragma mark Begin/End Session

- (void)didStartSession
{
  NSParameterAssert(self.currentState.lifecycle == FBSimulatorSessionLifecycleStateNotStarted);
  [self.generator updateLifecycle:FBSimulatorSessionLifecycleStateStarted];
  [self materializeNotification:FBSimulatorSessionDidStartNotification userInfo:@{}];
}

- (void)didEndSession
{
  NSParameterAssert(self.currentState.lifecycle == FBSimulatorSessionLifecycleStateStarted);

  // Stop all notifiers from firing first
  [self unregisterAllNotifiers];

  // Clean up other tasks
  [self.terminationHandlers makeObjectsPerformSelector:@selector(terminate)];
  self.terminationHandlers = nil;

  // If we reached here with a termination handle, terminate the simulator
  if (self.simulatorTerminationHandle) {
    id<FBTerminationHandle> handle = self.simulatorTerminationHandle;
    [self simulatorWillTerminate:self.session.simulator];
    [handle terminate];
  }

  // Tidy up the file handles too
  [self unregisterAllFileHandles];

  // Update State
  [self.generator updateLifecycle:FBSimulatorSessionLifecycleStateEnded];
  [self materializeNotification:FBSimulatorSessionDidEndNotification userInfo:@{}];
}

#pragma mark State

- (FBSimulatorSessionState *)currentState
{
  return self.generator.currentState;
}

#pragma mark - Private

#pragma mark Notifiers

- (void)createNotifierForBinary:(FBSimulatorBinary *)binary onProcessIdentifier:(NSInteger)processIdentifier withHandler:( void(^)(FBSimulatorSessionLifecycle *) )handler
{
  NSParameterAssert(self.notifiers[binary] == nil);

  __weak typeof(self) weakSelf = self;
  FBDispatchSourceNotifier *notifier = [FBDispatchSourceNotifier processTerminationNotifierForProcessIdentifier:processIdentifier handler:^(FBDispatchSourceNotifier *_) {
    handler(weakSelf);
  }];
  self.notifiers[binary] = notifier;
}

- (void)unregisterNotifierForBinary:(FBSimulatorBinary *)binary
{
  FBDispatchSourceNotifier *notifier = self.notifiers[binary];
  if (!notifier) {
    return;
  }
  [notifier terminate];
  [self.notifiers removeObjectForKey:binary];
}

- (void)unregisterAllNotifiers
{
  [self.notifiers.allValues makeObjectsPerformSelector:@selector(terminate)];
  [self.notifiers removeAllObjects];
}

#pragma mark File Handles

- (void)registerFileHandle:(NSFileHandle *)fileHandle forBinary:(FBSimulatorBinary *)binary
{
  if (!binary || !fileHandle) {
    return;
  }

  NSMutableSet *handles = self.fileHandles[binary];
  if (!handles) {
    handles = [NSMutableSet set];
    self.fileHandles[binary] = handles;
  }

  NSAssert(![handles containsObject:fileHandle], @"Cannot register the same file handle twice");
  [handles addObject:fileHandle];
}

- (void)unregisterFileHandlesForBinary:(FBSimulatorBinary *)binary
{
  NSMutableSet *handles = self.fileHandles[binary];
  [handles makeObjectsPerformSelector:@selector(closeFile)];
  [handles removeAllObjects];
  [self.fileHandles removeObjectForKey:binary];
}

- (void)unregisterAllFileHandles
{
  for (FBSimulatorBinary *binary in self.fileHandles.allKeys) {
    [self unregisterFileHandlesForBinary:binary];
  }
}

#pragma mark SimDevice Notifiers

- (void)registerSimDeviceNotifier:(FBSimulator *)simulator
{
  FBSimulatorSessionStateGenerator *generator = self.generator;
  FBCoreSimulatorNotifier *notifier = [FBCoreSimulatorNotifier notifierForSimulator:simulator block:^(NSDictionary *info) {
    if ([info[@"notification"] isEqualToString:@"device_state"] && [info[@"newState"] respondsToSelector:@selector(unsignedIntegerValue)]) {
      FBSimulatorState state = [info[@"new_state"] unsignedIntegerValue];
      [generator updateSimulatorState:state];
    }
  }];
  [self associateEndOfSessionCleanup:notifier];
}

#pragma mark Notifications

- (void)materializeNotification:(NSString *)notificationName withSubject:(id)subject
{
  [self materializeNotification:notificationName withSubject:subject expected:NO];
}

- (void)materializeNotification:(NSString *)notificationName withSubject:(id)subject expected:(BOOL)expected
{
  NSParameterAssert(subject);
  [self materializeNotification:notificationName userInfo:@{
    FBSimulatorSessionSubjectKey : subject,
    FBSimulatorSessionExpectedKey : @(expected),
    FBSimulatorSessionStateKey : self.currentState
  }];
}

- (void)materializeNotification:(NSString *)notificationName userInfo:(NSDictionary *)userInfo
{
  NSParameterAssert(notificationName);
  NSParameterAssert(userInfo);

  NSMutableDictionary *mergedInfo = [NSMutableDictionary dictionary];
  [mergedInfo addEntriesFromDictionary:userInfo];
  mergedInfo[FBSimulatorSessionStateKey] = self.currentState;

  [NSNotificationCenter.defaultCenter
   postNotificationName:notificationName
   object:self.session
   userInfo:[mergedInfo copy]];
}

@end
