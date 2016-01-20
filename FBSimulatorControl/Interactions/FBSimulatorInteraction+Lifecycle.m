/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction+Lifecycle.h"

#import <CoreSimulator/SimDevice.h>

#import "FBCollectionDescriptions.h"
#import "FBInteraction+Private.h"
#import "FBProcessInfo.h"
#import "FBProcessLaunchConfiguration.h"
#import "FBProcessTerminationStrategy.h"
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
#import "FBSimulatorInteraction+Private.h"
#import "FBSimulatorLaunchConfiguration+Helpers.h"
#import "FBSimulatorLaunchConfiguration.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorSession+Private.h"
#import "FBSimulatorTerminationStrategy.h"
#import "FBTaskExecutor.h"

@implementation FBSimulatorInteraction (Lifecycle)

- (instancetype)bootSimulator
{
  return [self bootSimulator:FBSimulatorLaunchConfiguration.defaultConfiguration];
}

- (instancetype)bootSimulator:(FBSimulatorLaunchConfiguration *)configuration
{
  NSParameterAssert(configuration);

  return [self interactWithShutdownSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    // Fetch the Boot arguments
    NSError *innerError = nil;
    NSArray *arguments = [configuration xcodeSimulatorApplicationArgumentsForSimulator:simulator error:&innerError];
    if (!arguments) {
      return [[[FBSimulatorError
        describeFormat:@"Failed to create boot args for Configuration %@", configuration]
        causedBy:innerError]
        failBool:error];
    }

    // Construct and start the task.
    id<FBTask> task = [[[[[FBTaskExecutor.sharedInstance
      withLaunchPath:FBSimulatorApplication.xcodeSimulator.binary.path]
      withArguments:[arguments copy]]
      withEnvironmentAdditions:@{ FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID : simulator.udid }]
      build]
      startAsynchronously];

    [simulator.eventSink terminationHandleAvailable:task];

    // Expect no immediate error.
    if (task.error) {
      return [[[[FBSimulatorError
        describe:@"Failed to Launch Simulator Process"]
        causedBy:task.error]
        inSimulator:simulator]
        failBool:error];
    }

    // Expect the state of the simulator to be updated.
    BOOL didBoot = [simulator waitOnState:FBSimulatorStateBooted];
    if (!didBoot) {
      return [[[FBSimulatorError
        describeFormat:@"Timed out waiting for device to be Booted, got %@", simulator.device.stateString]
        inSimulator:simulator]
        failBool:error];
    }


    // Expect the launch info for the process to exist.
    FBProcessQuery *processQuery = simulator.processQuery;
    FBProcessInfo *containerApplication = [simulator.processQuery simulatorApplicationProcessForSimDevice:simulator.device];
    if (!containerApplication) {
      return [[[FBSimulatorError
        describe:@"Could not obtain process info for container application"]
        inSimulator:simulator]
        failBool:error];
    }
    [simulator.eventSink containerApplicationDidLaunch:containerApplication];

    // Expect the launchd_sim process to be updated.
    FBProcessInfo *launchdSimProcess = [processQuery launchdSimProcessForSimDevice:simulator.device];
    if (!launchdSimProcess) {
      return [[[FBSimulatorError
        describe:@"Could not obtain process info for launchd_sim process"]
        inSimulator:simulator]
        failBool:error];
    }
    [simulator.eventSink simulatorDidLaunch:launchdSimProcess];

    // Waitng for all required processes to start
    NSSet *requiredProcessNames = simulator.requiredProcessNamesToVerifyBooted;
    BOOL didStartAllRequiredProcesses = [NSRunLoop.mainRunLoop spinRunLoopWithTimeout:FBSimulatorControlGlobalConfiguration.slowTimeout untilTrue:^ BOOL {
      NSSet *runningProcessNames = [NSSet setWithArray:[[processQuery subprocessesOf:launchdSimProcess.processIdentifier] valueForKey:@"processName"]];
      return [requiredProcessNames isSubsetOfSet:runningProcessNames];
    }];
    if (!didStartAllRequiredProcesses) {
      return [[[FBSimulatorError
        describeFormat:@"Timed out waiting for all required processes %@ to start", [FBCollectionDescriptions oneLineDescriptionFromArray:requiredProcessNames.allObjects]]
        inSimulator:simulator]
        failBool:error];
    }

    // Pass on the success to the event sink.
    [simulator.eventSink containerApplicationDidLaunch:containerApplication];

    return YES;
  }];
}

- (instancetype)shutdownSimulator
{
  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    FBProcessInfo *containerApplication = simulator.containerApplication;
    FBProcessInfo *launchdSimProcess = simulator.launchdSimProcess;

    FBSimulatorTerminationStrategy *terminationStrategy = [FBSimulatorTerminationStrategy
      withConfiguration:simulator.pool.configuration
      processQuery:simulator.processQuery
      logger:simulator.pool.logger];

    NSError *innerError = nil;
    if (![terminationStrategy killSimulators:@[simulator] withError:&innerError]) {
      return [[[[FBSimulatorError describe:@"Could not shutdown simulator"] inSimulator:simulator] causedBy:innerError] failBool:error];
    }
    [simulator.eventSink containerApplicationDidTerminate:containerApplication expected:YES];
    [simulator.eventSink simulatorDidTerminate:launchdSimProcess expected:YES];

    return YES;
  }];
}

- (instancetype)openURL:(NSURL *)url
{
  NSParameterAssert(url);

  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    NSError *innerError = nil;
    if (![simulator.device openURL:url error:&innerError]) {
      NSString *description = [NSString stringWithFormat:@"Failed to open URL %@ on simulator %@", url, simulator];
      return [FBSimulatorError failBoolWithError:innerError description:description errorOut:error];
    }
    return YES;
  }];
}

- (instancetype)signal:(int)signo process:(FBProcessInfo *)process
{
  NSParameterAssert(process);

  return [self process:process interact:^ BOOL (NSError **error, FBSimulator *simulator) {
    // Confirm that the process has the launchd_sim as a parent process.
    // The interaction should restrict itself to simulator processes so this is a guard
    // to ensure that this interaction can't go around killing random processes.
    pid_t parentProcessIdentifier = [simulator.processQuery parentOf:process.processIdentifier];
    if (parentProcessIdentifier != simulator.launchdSimProcess.processIdentifier) {
      return [[FBSimulatorError
        describeFormat:@"Parent of %@ is not the launchd_sim (%@) it has a pid %d", process.shortDescription, simulator.launchdSimProcess.shortDescription, parentProcessIdentifier]
        failBool:error];
    }

    // Notify the eventSink of the process getting killed, before it is killed.
    // This is done to prevent being marked as an unexpected termination when the
    // detecting of the process getting killed kicks in.
    FBProcessLaunchConfiguration *configuration = simulator.history.processLaunchConfigurations[process];
    if ([configuration isKindOfClass:FBApplicationLaunchConfiguration.class]) {
      [simulator.eventSink applicationDidTerminate:process expected:YES];
    } else if ([configuration isKindOfClass:FBAgentLaunchConfiguration.class]) {
      [simulator.eventSink agentDidTerminate:process expected:YES];
    }

    // Use FBProcessTerminationStrategy to do the actual process killing.
    NSError *innerError = nil;
    if (![[FBProcessTerminationStrategy withProcessKilling:simulator.processQuery logger:simulator.logger] killProcess:process error:&innerError]) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }

    return YES;
  }];
}

- (instancetype)killProcess:(FBProcessInfo *)process
{
  return [self signal:SIGKILL process:process];
}

@end
