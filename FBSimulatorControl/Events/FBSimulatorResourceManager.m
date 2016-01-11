/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorResourceManager.h"

#import "FBProcessInfo.h"
#import "FBTerminationHandle.h"

@interface FBTerminationHandle_NSFileHandle : NSObject <FBTerminationHandle>

@property (nonatomic, strong, readonly) NSFileHandle *fileHandle;

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

@property (nonatomic, strong, readonly) NSMutableDictionary *processToHandles;
@property (nonatomic, strong, readonly) NSMutableArray *simulatorTerminationHandles;

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

  return self;
}

#pragma mark FBSimulatorEventSink Implementation

- (void)containerApplicationDidLaunch:(FBProcessInfo *)applicationProcess
{

}

- (void)containerApplicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
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

- (void)applicationDidLaunch:(FBApplicationLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)applicationProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  [self addHandlesForProcess:applicationProcess stdOut:stdOut stdErr:stdErr];
}

- (void)applicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{
  [self terminateHandlesAssociatedWithProcess:applicationProcess];
}

- (void)diagnosticInformationAvailable:(NSString *)name process:(FBProcessInfo *)process value:(id<NSCopying, NSCoding>)value
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
  [self.processToHandles.allValues makeObjectsPerformSelector:@selector(terminate)];
  [self.processToHandles removeAllObjects];
  [self.simulatorTerminationHandles makeObjectsPerformSelector:@selector(terminate)];
  [self.simulatorTerminationHandles removeAllObjects];
}

@end
