/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction.h"
#import "FBSimulatorInteraction+Private.h"

#import <CoreSimulator/SimDevice.h>

#import "FBCollectionDescriptions.h"
#import "FBInteraction+Private.h"
#import "FBProcessLaunchConfiguration.h"
#import "FBProcessQuery+Simulators.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorControlGlobalConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorSession+Private.h"
#import "FBSimulatorTerminationStrategy.h"
#import "FBTaskExecutor.h"

@implementation FBSimulatorInteraction

+ (instancetype)withSimulator:(FBSimulator *)simulator
{
  FBSimulatorInteraction *interaction = [self new];
  interaction.simulator = simulator;
  return interaction;
}

#pragma mark Private

- (instancetype)interactWithSimulator:(BOOL (^)(NSError **error, FBSimulator *simulator))block
{
  return [self interact:^ BOOL (NSError **error, FBSimulatorInteraction *interaction) {
    return block(error, interaction.simulator);
  }];
}

- (instancetype)interactWithSimulatorAtState:(FBSimulatorState)state block:(BOOL (^)(NSError **error, FBSimulator *simulator))block
{
  return [self interactWithSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    if (simulator.state != state) {
      return [[[FBSimulatorError
        describeFormat:@"Expected Simulator %@ to be %@, but it was '%@'", simulator.udid, simulator.stateString, [FBSimulator stateStringFromSimulatorState:simulator.state]]
        inSimulator:simulator]
        failBool:error];
    }
    return block(error, simulator);
  }];
}

- (instancetype)interactWithShutdownSimulator:(BOOL (^)(NSError **error, FBSimulator *simulator))block
{
  return [self interactWithSimulatorAtState:FBSimulatorStateShutdown block:block];
}

- (instancetype)interactWithBootedSimulator:(BOOL (^)(NSError **error, FBSimulator *simulator))block
{
  return [self interactWithSimulatorAtState:FBSimulatorStateBooted block:block];
}

- (instancetype)process:(FBProcessInfo *)process interact:(BOOL (^)(NSError **error, FBSimulator *simulator))block
{
  NSParameterAssert(process);
  NSParameterAssert(block);

  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    FBProcessInfo *launchdSimProcess = simulator.launchdSimProcess;
    pid_t ppid = [simulator.processQuery parentOf:process.processIdentifier];
    if (launchdSimProcess.processIdentifier != ppid) {
      return [[FBSimulatorError
        describeFormat:@"Process %@ has parent %d but should have parent %@", process.shortDescription, ppid, launchdSimProcess.shortDescription]
        failBool:error];
    }
    return block(error, simulator);
  }];
}

- (instancetype)binary:(FBSimulatorBinary *)binary interact:(BOOL (^)(NSError **error, FBSimulator *simulator, FBProcessInfo *process))block
{
  NSParameterAssert(binary);
  NSParameterAssert(block);

  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    FBProcessInfo *processInfo = [[[simulator
      launchdSimSubprocesses]
      filteredArrayUsingPredicate:[FBProcessQuery processesForBinary:binary]]
      firstObject];

    if (!processInfo) {
      return [[[FBSimulatorError describeFormat:@"Could not find an active process for %@", binary] inSimulator:simulator] failBool:error];
    }
    return block(error, simulator, processInfo);
  }];
}

@end
