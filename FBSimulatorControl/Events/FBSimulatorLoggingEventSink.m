/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorLoggingEventSink.h"

#import "FBProcessInfo.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator.h"
#import "FBSimulatorControlGlobalConfiguration.h"
#import "FBWritableLog.h"

@interface FBSimulatorLoggingEventSink ()

@property (nonatomic, strong, readonly) id<FBSimulatorLogger> logger;
@property (nonatomic, copy, readonly) NSString *prefix;

@end

@implementation FBSimulatorLoggingEventSink

#pragma mark Initializers

+ (instancetype)withSimulator:(FBSimulator *)simulator logger:(id<FBSimulatorLogger>)logger
{
  return [[self alloc] initWithPrefix:[NSString stringWithFormat:@"%@: ", simulator.udid] logger:logger.info];
}

- (instancetype)initWithPrefix:(NSString *)prefix logger:(id<FBSimulatorLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _prefix = prefix;
  _logger = logger;

  return self;
}

#pragma mark FBSimulatorEventSink Implementation

- (void)containerApplicationDidLaunch:(FBProcessInfo *)applicationProcess
{
  [self.logger logFormat:@"%@Container Application Did Launch => %@", self.prefix, applicationProcess.shortDescription];
}

- (void)containerApplicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{
  [self.logger logFormat:@"%@Container Application Did Terminate => %@ Expected %d", self.prefix, applicationProcess.shortDescription, expected];
}

- (void)simulatorDidLaunch:(FBProcessInfo *)launchdSimProcess
{
  [self.logger logFormat:@"%@Simulator Did launch => %@", self.prefix, launchdSimProcess.shortDescription];
}

- (void)simulatorDidTerminate:(FBProcessInfo *)launchdSimProcess expected:(BOOL)expected
{
  [self.logger logFormat:@"%@Simulator Did Terminate => %@ Expected %d", self.prefix, launchdSimProcess.shortDescription, expected];
}

- (void)agentDidLaunch:(FBAgentLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)agentProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  [self.logger logFormat:@"%@Agent Did Launch => %@", self.prefix, agentProcess.shortDescription];
}

- (void)agentDidTerminate:(FBProcessInfo *)agentProcess expected:(BOOL)expected
{
  [self.logger logFormat:@"%@Agent Did Terminate => Expected %d %@ ", self.prefix, expected, agentProcess.shortDescription];
}

- (void)applicationDidLaunch:(FBApplicationLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)applicationProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  [self.logger logFormat:@"%@Application Did Launch => %@", self.prefix, applicationProcess.shortDescription];
}

- (void)applicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{
  [self.logger logFormat:@"%@Application Did Terminate => Expected %d %@", self.prefix, expected, applicationProcess.shortDescription];
}

- (void)logAvailable:(FBWritableLog *)log
{
  [self.logger logFormat:@"%@Log Available => %@", self.prefix, log.shortDescription];
}

- (void)didChangeState:(FBSimulatorState)state
{
  [self.logger logFormat:@"%@Did Change State => %@", self.prefix, [FBSimulator stateStringFromSimulatorState:state]];
}

- (void)terminationHandleAvailable:(id<FBTerminationHandle>)terminationHandle
{

}

@end
