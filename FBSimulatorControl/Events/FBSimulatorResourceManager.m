/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorResourceManager.h"

#import <FBControlCore/FBControlCore.h>

@interface FBTerminationHandle_NSFileHandle : NSObject <FBTerminationHandle>

@property (nonatomic, strong, readonly, nonnull) NSFileHandle *fileHandle;

@end

@implementation FBTerminationHandle_NSFileHandle

- (instancetype)initWithFileHandle:(NSFileHandle *)fileHandle
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _fileHandle = fileHandle;
  return self;
}

- (void)terminate
{
  [self.fileHandle closeFile];
}

@end

@interface FBSimulatorResourceManager ()
@property (nonatomic, strong, readonly, nonnull) NSMutableSet<FBTestManager *> *mutableTestManagers;
@property (nonatomic, strong, readonly, nonnull) NSMutableDictionary<FBProcessInfo *, NSMutableArray<FBTerminationHandle *> *> *processToHandles;
@property (nonatomic, strong, readonly, nonnull) NSMutableArray<FBTerminationHandle *> *simulatorTerminationHandles;

@end

@implementation FBSimulatorResourceManager

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _processToHandles = [NSMutableDictionary dictionary];
  _simulatorTerminationHandles = [NSMutableArray array];
  _mutableTestManagers = [NSMutableSet set];
  return self;
}

- (NSSet<FBTestManager *> *)testManagers
{
  return self.mutableTestManagers.copy;
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
  [self terminateAllHandles];
}

- (void)agentDidLaunch:(FBAgentLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)agentProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  [self addHandlesForProcess:agentProcess stdOut:stdOut stdErr:stdErr];
}

- (void)agentDidTerminate:(FBProcessInfo *)agentProcess expected:(BOOL)expected
{
  [self terminateHandlesAssociatedWithProcess:agentProcess];
}

- (void)applicationDidLaunch:(FBApplicationLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)applicationProcess
{

}

- (void)applicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{

}

- (void)testmanagerDidConnect:(FBTestManager *)testManager
{
  [self.mutableTestManagers addObject:testManager];
}

- (void)testmanagerDidDisconnect:(FBTestManager *)testManager
{
  [self.mutableTestManagers removeObject:testManager];
}

- (void)diagnosticAvailable:(FBDiagnostic *)diagnostic
{

}

- (void)didChangeState:(FBSimulatorState)state
{

}

- (void)terminationHandleAvailable:(id<FBTerminationHandle>)terminationHandle
{
  [self.simulatorTerminationHandles addObject:terminationHandle];
}

#pragma mark Private

- (void)addHandlesForProcess:(FBProcessInfo *)process stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  if (stdOut) {
    [self addTerminationHandle:[[FBTerminationHandle_NSFileHandle alloc] initWithFileHandle:stdOut] forProcess:process];
  }
  if (stdErr) {
    [self addTerminationHandle:[[FBTerminationHandle_NSFileHandle alloc] initWithFileHandle:stdErr] forProcess:process];
  }
}

- (void)addTerminationHandle:(id<FBTerminationHandle>)handle forProcess:(FBProcessInfo *)processInfo
{
  NSMutableArray *handles = self.processToHandles[processInfo];
  if (!handles) {
    handles = [NSMutableArray array];
    self.processToHandles[processInfo] = handles;
  }
  [handles addObject:handle];
}

- (void)terminateHandlesAssociatedWithProcess:(FBProcessInfo *)processInfo
{
  NSArray *handles = self.processToHandles[processInfo];
  [handles makeObjectsPerformSelector:@selector(terminate)];
  [self.processToHandles removeObjectForKey:processInfo];
}

- (void)terminateAllHandles
{
  for (FBProcessInfo *processInfo in self.processToHandles) {
    [self terminateHandlesAssociatedWithProcess:processInfo];
  }
  [self.processToHandles removeAllObjects];
  [self.simulatorTerminationHandles makeObjectsPerformSelector:@selector(terminate)];
  [self.simulatorTerminationHandles removeAllObjects];
  [self.mutableTestManagers removeAllObjects];
}

@end
