/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorSubprocessTerminationStrategy.h"

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator.h"
#import "FBSimulator+Private.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulatorLaunchCtl.h"
#import "FBSimulatorHistory.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorProcessFetcher.h"

@interface FBSimulatorSubprocessTerminationStrategy ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorSubprocessTerminationStrategy

+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator
{
  return [[self alloc] initWithSimulator:simulator];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;

  return self;
}

- (BOOL)terminate:(FBProcessInfo *)process error:(NSError **)error
{
  // Confirm that the process has the launchd_sim as a parent process.
  // The interaction should restrict itself to simulator processes so this is a guard
  // to ensure that this interaction can't go around killing random processes.
  pid_t parentProcessIdentifier = [self.simulator.processFetcher.processFetcher parentOf:process.processIdentifier];
  if (parentProcessIdentifier != self.simulator.launchdProcess.processIdentifier) {
    return [[FBSimulatorError
      describeFormat:@"Parent of %@ is not the launchd_sim (%@) it has a pid %d", process.shortDescription, self.simulator.launchdProcess.shortDescription, parentProcessIdentifier]
      failBool:error];
  }

  // Notify the eventSink of the process getting killed, before it is killed.
  // This is done to prevent being marked as an unexpected termination when the
  // detecting of the process getting killed kicks in.
  // If there is no record of this process, no notification is sent.
  FBProcessLaunchConfiguration *configuration = self.simulator.history.processLaunchConfigurations[process];
  if ([configuration isKindOfClass:FBApplicationLaunchConfiguration.class]) {
    [self.simulator.eventSink applicationDidTerminate:process expected:YES];
  } else if ([configuration isKindOfClass:FBAgentLaunchConfiguration.class]) {
    [self.simulator.eventSink agentDidTerminate:process expected:YES];
  }

  // Get the Service Name and then stop using the Service Name.
  NSError *innerError = nil;
  NSString *serviceName = [self.simulator.launchctl serviceNameForProcess:process error:&innerError];
  if (!serviceName) {
    return [[FBSimulatorError
      describeFormat:@"Could not Obtain the Service Name for %@", process.shortDescription]
      failBool:error];
  }

  [self.simulator.logger.debug logFormat:@"Stopping Service '%@'", serviceName];
  if (![self.simulator.launchctl stopServiceWithName:serviceName error:&innerError]) {
    return [[FBSimulatorError
      describeFormat:@"Failed to stop service '%@'", serviceName]
      failBool:error];
  }
  [self.simulator.logger.debug logFormat:@"Stopped Service '%@'", serviceName];
  return YES;
}

@end
