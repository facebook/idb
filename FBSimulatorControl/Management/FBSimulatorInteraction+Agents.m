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

#import "FBInteraction+Private.h"
#import "FBProcessInfo.h"
#import "FBProcessLaunchConfiguration+Helpers.h"
#import "FBProcessLaunchConfiguration.h"
#import "FBProcessQuery.h"
#import "FBSimDeviceWrapper.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorError.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorSessionLifecycle.h"

@implementation FBSimulatorInteraction (Agents)

- (instancetype)launchAgent:(FBAgentLaunchConfiguration *)agentLaunch
{
  NSParameterAssert(agentLaunch);

  FBSimulator *simulator = self.simulator;
  FBSimulatorSessionLifecycle *lifecycle = self.lifecycle;

  return [self interact:^ BOOL (NSError **error, id _) {
    NSError *innerError = nil;
    NSFileHandle *stdOut = nil;
    NSFileHandle *stdErr = nil;
    if (![agentLaunch createFileHandlesWithStdOut:&stdOut stdErr:&stdErr error:&innerError]) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }

    NSDictionary *options = [agentLaunch agentLaunchOptionsWithStdOut:stdOut stdErr:stdErr error:error];
    if (!options) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }

    id<FBProcessInfo> process = [[FBSimDeviceWrapper withSimDevice:simulator.device configuration:simulator.pool.configuration processQuery:simulator.processQuery]
      spawnWithPath:agentLaunch.agentBinary.path
      options:options
      terminationHandler:NULL
      error:&innerError];

    if (!process) {
      return [[[[FBSimulatorError describeFormat:@"Failed to start Agent %@", agentLaunch] causedBy:innerError] inSimulator:simulator] failBool:error];
    }

    [lifecycle agentDidLaunch:agentLaunch didStartWithProcessIdentifier:process.processIdentifier stdOut:stdOut stdErr:stdErr];
    return YES;
  }];
}

- (instancetype)killAgent:(FBSimulatorBinary *)agent
{
  NSParameterAssert(agent);

  FBSimulator *simulator = self.simulator;
  FBSimulatorSessionLifecycle *lifecycle = self.lifecycle;

  return [self binary:agent interact:^ BOOL (id<FBProcessInfo> process, NSError **error) {
    [lifecycle agentWillTerminate:agent];
    if (!kill(process.processIdentifier, SIGKILL)) {
      return [[[FBSimulatorError describeFormat:@"SIGKILL of Agent %@ of PID %d failed", agent, process.processIdentifier] inSimulator:simulator] failBool:error];
    }
    return YES;
  }];
}

@end
