/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBAgentLaunchStrategy.h"

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator+Helpers.h"
#import "FBProcessLaunchConfiguration+Helpers.h"
#import "FBSimDeviceWrapper.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorError.h"
#import "FBSimulatorApplication.h"
#import "FBProcessLaunchConfiguration.h"

@interface FBAgentLaunchStrategy ()

@property (nonnull, nonatomic, strong, readonly) FBSimulator *simulator;

@end

@implementation FBAgentLaunchStrategy

+ (instancetype)withSimulator:(FBSimulator *)simulator
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

- (nullable FBProcessInfo *)launchAgent:(FBAgentLaunchConfiguration *)agentLaunch error:(NSError **)error;
{
  FBSimulator *simulator = self.simulator;
  NSError *innerError = nil;
  NSFileHandle *stdOut = nil;
  NSFileHandle *stdErr = nil;
  if (![agentLaunch createFileHandlesWithStdOut:&stdOut stdErr:&stdErr error:&innerError]) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  NSDictionary *options = [agentLaunch simDeviceLaunchOptionsWithStdOut:stdOut stdErr:stdErr];
  if (!options) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  FBProcessInfo *process = [simulator.simDeviceWrapper
    spawnLongRunningWithPath:agentLaunch.agentBinary.path
    options:options
    terminationHandler:NULL
    error:&innerError];

  if (!process) {
    return [[[[FBSimulatorError
      describeFormat:@"Failed to start Agent %@", agentLaunch]
      causedBy:innerError]
      inSimulator:simulator]
      fail:error];
  }

  [simulator.eventSink agentDidLaunch:agentLaunch didStart:process stdOut:stdOut stdErr:stdErr];
  return process;
}

@end
