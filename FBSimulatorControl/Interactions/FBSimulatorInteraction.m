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
#import "FBSimulatorControlStaticConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorLaunchInfo.h"
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

- (instancetype)bootSimulator
{
  FBSimulator *simulator = self.simulator;

  return [self interact:^ BOOL (NSError **error, id _) {
    if (!simulator.simulatorApplication) {
      return [[FBSimulatorError describe:@"Could not boot Simulator as no Simulator Application was provided"] failBool:error];
    }

    // Construct the Arguments
    NSMutableArray *arguments = [NSMutableArray arrayWithArray:@[
      @"--args",
      @"-CurrentDeviceUDID", simulator.udid,
      @"-ConnectHardwareKeyboard", @"0"
    ]];
    NSArray *scaleArguments = [simulator.configuration lastScaleCommandLineArgumentsWithError:nil];
    if (scaleArguments) {
      [arguments addObjectsFromArray:scaleArguments];
    }
    if (simulator.pool.configuration.deviceSetPath) {
      if (!FBSimulatorControlStaticConfiguration.supportsCustomDeviceSets) {
        return [[[FBSimulatorError describe:@"Cannot use custom Device Set on current platform"] inSimulator:simulator] failBool:error];
      }
      [arguments addObjectsFromArray:@[@"-DeviceSetPath", simulator.pool.configuration.deviceSetPath]];
    }

    // Construct and start the task.
    id<FBTask> task = [[[[[FBTaskExecutor.sharedInstance
      withLaunchPath:simulator.simulatorApplication.binary.path]
      withArguments:[arguments copy]]
      withEnvironmentAdditions:@{ FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID : simulator.udid }]
      build]
      startAsynchronously];

    // Expect no immediate error.
    if (task.error) {
      return [[[[FBSimulatorError describe:@"Failed to Launch Simulator Process"] causedBy:task.error] inSimulator:simulator] failBool:error];
    }

    // Expect the state of the simulator to be updated.
    BOOL didBoot = [simulator waitOnState:FBSimulatorStateBooted];
    if (!didBoot) {
      return [[[FBSimulatorError describeFormat:@"Timed out waiting for device to be Booted, got %@", simulator.device.stateString] inSimulator:simulator] failBool:error];
    }

    // Expect the launch info for the process to exist.
    FBSimulatorLaunchInfo *launchInfo = [FBSimulatorLaunchInfo fromSimDevice:simulator.device query:simulator.processQuery];
    if (!launchInfo) {
      return [[[FBSimulatorError describe:@"Could not obtain process info for booted simulator process"] inSimulator:simulator] failBool:error];
    }

    // Waitng for all required processes to start
    NSSet *requiredProcesses = simulator.requiredProcessNamesToVerifyBooted;
    BOOL didStartAllRequiredProcesses = [NSRunLoop.mainRunLoop spinRunLoopWithTimeout:60 untilTrue:^ BOOL {
      NSSet *runningProcesses = [NSSet setWithArray:[simulator.processQuery subprocessesOf:launchInfo.launchdProcess.processIdentifier]];
      runningProcesses = [runningProcesses valueForKey:@"processName"];
      return [requiredProcesses isSubsetOfSet:runningProcesses];
    }];
    if (!didStartAllRequiredProcesses) {
      return [[[FBSimulatorError
        describeFormat:@"Timed out waiting for all required processes %@ to start", [FBCollectionDescriptions oneLineDescriptionFromArray:requiredProcesses.allObjects]]
        inSimulator:simulator]
        failBool:error];
    }

    // Pass on the success to the event sink.
    [simulator.eventSink didStartWithLaunchInfo:launchInfo];
    [simulator.eventSink terminationHandleAvailable:task];

    return YES;
  }];
}

- (instancetype)shutdownSimulator
{
  FBSimulator *simulator = self.simulator;

  return [self interact:^ BOOL (NSError **error, id _) {
    FBSimulatorLaunchInfo *launchInfo = simulator.launchInfo;
    if (!launchInfo) {
      return [[[FBSimulatorError describe:@"Could not shutdown simulator as there is no available launch info"] inSimulator:simulator] failBool:error];
    }

    FBSimulatorTerminationStrategy *terminationStrategy = [FBSimulatorTerminationStrategy
      withConfiguration:simulator.pool.configuration
      processQuery:simulator.processQuery];

    NSError *innerError = nil;
    if (![terminationStrategy killSimulators:@[simulator] withError:&innerError]) {
      return [[[[FBSimulatorError describe:@"Could not shutdown simulator"] inSimulator:simulator] causedBy:innerError] failBool:error];
    }
    [simulator.eventSink didTerminate:YES];

    return YES;
  }];
}

- (instancetype)openURL:(NSURL *)url
{
  NSParameterAssert(url);

  FBSimulator *simulator = self.simulator;

  return [self interact:^ BOOL (NSError **error, id _) {
    NSError *innerError = nil;
    if (![simulator.device openURL:url error:&innerError]) {
      NSString *description = [NSString stringWithFormat:@"Failed to open URL %@ on simulator %@", url, simulator];
      return [FBSimulatorError failBoolWithError:innerError description:description errorOut:error];
    }
    return YES;
  }];
}

#pragma mark Private

- (instancetype)binary:(FBSimulatorBinary *)binary interact:(BOOL (^)(FBProcessInfo *process, NSError **error))block
{
  NSParameterAssert(binary);
  NSParameterAssert(block);

  FBSimulator *simulator = self.simulator;

  return [self interact:^ BOOL (NSError **error, id _) {
    FBProcessInfo *processInfo = [[[[simulator
      launchInfo]
      launchedProcesses]
      filteredArrayUsingPredicate:[FBProcessQuery processesForBinary:binary]]
      firstObject];

    if (!processInfo) {
      return [[[FBSimulatorError describeFormat:@"Could not find an active process for %@", binary] inSimulator:simulator] failBool:error];
    }
    return block(processInfo, error);
  }];
}

@end
