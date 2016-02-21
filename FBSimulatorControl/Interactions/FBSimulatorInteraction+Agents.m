/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction+Agents.h"

#import <CoreSimulator/SimDevice.h>

#import "FBProcessInfo.h"
#import "FBProcessLaunchConfiguration+Helpers.h"
#import "FBProcessLaunchConfiguration.h"
#import "FBProcessQuery.h"
#import "FBSimDeviceWrapper.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBSimulatorPool.h"

@implementation FBSimulatorInteraction (Agents)

- (instancetype)launchAgent:(FBAgentLaunchConfiguration *)agentLaunch
{
  NSParameterAssert(agentLaunch);

  return [self interactWithBootedSimulator:^ BOOL (id _, NSError **error, FBSimulator *simulator) {
    NSError *innerError = nil;
    NSFileHandle *stdOut = nil;
    NSFileHandle *stdErr = nil;
    if (![agentLaunch createFileHandlesWithStdOut:&stdOut stdErr:&stdErr error:&innerError]) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }

    NSDictionary *options = [agentLaunch simDeviceLaunchOptionsWithStdOut:stdOut stdErr:stdErr];
    if (!options) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }

    FBProcessInfo *process = [simulator.simDeviceWrapper
      spawnLongRunningWithPath:agentLaunch.agentBinary.path
      options:options
      terminationHandler:NULL
      error:&innerError];

    if (!process) {
      return [[[[FBSimulatorError describeFormat:@"Failed to start Agent %@", agentLaunch] causedBy:innerError] inSimulator:simulator] failBool:error];
    }

    [simulator.eventSink agentDidLaunch:agentLaunch didStart:process stdOut:stdOut stdErr:stdErr];
    return YES;
  }];
}

- (instancetype)killAgent:(FBSimulatorBinary *)agent
{
  NSParameterAssert(agent);

  return [self binary:agent interact:^ BOOL (id _, NSError **error, FBSimulator *simulator, FBProcessInfo *process) {
    if (!kill(process.processIdentifier, SIGKILL)) {
      return [[[FBSimulatorError describeFormat:@"SIGKILL of Agent %@ of PID %d failed", agent, process.processIdentifier] inSimulator:simulator] failBool:error];
    }
    [self.simulator.eventSink agentDidTerminate:process expected:YES];
    return YES;
  }];
}

@end
