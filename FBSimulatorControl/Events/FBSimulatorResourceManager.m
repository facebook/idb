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

@interface FBSimulatorResourceManager ()

@property (nonatomic, strong, readonly) NSMutableSet<FBTestManager *> *mutableTestManagers;
@property (nonatomic, strong, readonly) NSMutableArray<id<FBTerminationHandle>> *simulatorTerminationHandles;

@end

@implementation FBSimulatorResourceManager

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

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

- (void)connectionDidConnect:(FBSimulatorConnection *)connection
{

}

- (void)connectionDidDisconnect:(FBSimulatorConnection *)connection expected:(BOOL)expected
{

}

- (void)simulatorDidLaunch:(FBProcessInfo *)launchdProcess
{

}

- (void)simulatorDidTerminate:(FBProcessInfo *)launchdProcess expected:(BOOL)expected
{
  [self terminateAllHandles];
}

- (void)agentDidLaunch:(FBSimulatorAgentOperation *)operation
{
}

- (void)agentDidTerminate:(FBSimulatorAgentOperation *)operation statLoc:(int)statLoc
{

}

- (void)applicationDidLaunch:(FBSimulatorApplicationOperation *)operation
{

}

- (void)applicationDidTerminate:(FBSimulatorApplicationOperation *)operation expected:(BOOL)expected
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

- (void)terminateAllHandles
{
  [self.simulatorTerminationHandles makeObjectsPerformSelector:@selector(terminate)];
  [self.simulatorTerminationHandles removeAllObjects];
  [self.mutableTestManagers removeAllObjects];
}

@end
