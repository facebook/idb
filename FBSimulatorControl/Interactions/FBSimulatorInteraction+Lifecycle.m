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
#import "FBSimulatorInteraction+Private.h"
#import "FBSimulatorLaunchConfiguration+Helpers.h"
#import "FBSimulatorLaunchConfiguration.h"
#import "FBSimulatorLaunchInfo.h"
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
    FBSimulatorLaunchInfo *launchInfo = [FBSimulatorLaunchInfo launchedViaApplicationOfSimDevice:simulator.device query:simulator.processQuery];
    if (!launchInfo) {
      return [[[FBSimulatorError describe:@"Could not obtain process info for booted simulator process"] inSimulator:simulator] failBool:error];
    }

    // Waitng for all required processes to start
    NSSet *requiredProcessNames = simulator.requiredProcessNamesToVerifyBooted;
    BOOL didStartAllRequiredProcesses = [NSRunLoop.mainRunLoop spinRunLoopWithTimeout:FBSimulatorControlGlobalConfiguration.slowTimeout untilTrue:^ BOOL {
      NSSet *runningProcessNames = [NSSet setWithArray:[launchInfo.launchedProcesses valueForKey:@"processName"]];
      return [requiredProcessNames isSubsetOfSet:runningProcessNames];
    }];
    if (!didStartAllRequiredProcesses) {
      return [[[FBSimulatorError
        describeFormat:@"Timed out waiting for all required processes %@ to start", [FBCollectionDescriptions oneLineDescriptionFromArray:requiredProcessNames.allObjects]]
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
  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    FBSimulatorLaunchInfo *launchInfo = simulator.launchInfo;
    if (!launchInfo) {
      return [[[FBSimulatorError describe:@"Could not shutdown simulator as there is no available launch info"] inSimulator:simulator] failBool:error];
    }

    FBSimulatorTerminationStrategy *terminationStrategy = [FBSimulatorTerminationStrategy
      withConfiguration:simulator.pool.configuration
      processQuery:simulator.processQuery
      logger:simulator.pool.logger];

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

  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    NSError *innerError = nil;
    if (![simulator.device openURL:url error:&innerError]) {
      NSString *description = [NSString stringWithFormat:@"Failed to open URL %@ on simulator %@", url, simulator];
      return [FBSimulatorError failBoolWithError:innerError description:description errorOut:error];
    }
    return YES;
  }];
}

@end
