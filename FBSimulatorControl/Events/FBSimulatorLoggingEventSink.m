/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorLoggingEventSink.h"

#import "FBSimulator.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulatorControlStaticConfiguration.h"

@interface FBSimulatorLoggingEventSink ()

@property (nonatomic, strong, readonly) id<FBSimulatorLogger> logger;
@property (nonatomic, copy, readonly) NSString *prefix;

@end

@implementation FBSimulatorLoggingEventSink

#pragma mark Initializers

+ (instancetype)withSimulator:(FBSimulator *)simulator logger:(id<FBSimulatorLogger>)logger
{
  return [[self alloc] initWithPrefix:[NSString stringWithFormat:@"%@: ", simulator.udid] logger:logger];
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

- (void)didStartWithLaunchInfo:(FBSimulatorLaunchInfo *)launchInfo
{
  [self.logger logMessage:@"%@Did Start => %@", self.prefix, launchInfo];
}

- (void)didTerminate:(BOOL)expected
{
  [self.logger logMessage:@"%@Did Terminate => Expected %d", self.prefix, expected];
}

- (void)agentDidLaunch:(FBAgentLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)agentProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  [self.logger logMessage:@"%@Agent Did Launch => %@", self.prefix, agentProcess];
}

- (void)agentDidTerminate:(FBProcessInfo *)agentProcess expected:(BOOL)expected
{
  [self.logger logMessage:@"%@Agent Did Terminate => Expected %d %@ ", self.prefix, expected, agentProcess];
}

- (void)applicationDidLaunch:(FBApplicationLaunchConfiguration *)launchConfig didStart:(FBProcessInfo *)applicationProcess stdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  [self.logger logMessage:@"%@Application Did Launch => %@", self.prefix, applicationProcess];
}

- (void)applicationDidTerminate:(FBProcessInfo *)applicationProcess expected:(BOOL)expected
{
  [self.logger logMessage:@"%@Application Did Terminate => Expected %d %@", self.prefix, expected, applicationProcess];
}

- (void)diagnosticInformationAvailable:(NSString *)name process:(FBProcessInfo *)process value:(id<NSCopying, NSCoding>)value
{
  [self.logger logMessage:@"%@Diagnostic Information Available => %@", self.prefix, name];
}

- (void)didChangeState:(FBSimulatorState)state
{
  [self.logger logMessage:@"%@Did Change State => %@", self.prefix, [FBSimulator stateStringFromSimulatorState:state]];
}

- (void)terminationHandleAvailable:(id<FBTerminationHandle>)terminationHandle
{

}

@end
