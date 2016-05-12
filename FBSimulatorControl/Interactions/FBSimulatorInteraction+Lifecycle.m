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

#import <FBControlCore/FBControlCore.h>

#import <SimulatorKit/SimDeviceFramebufferService.h>

#import "FBProcessLaunchConfiguration.h"
#import "FBProcessFetcher+Simulators.h"
#import "FBProcessTerminationStrategy.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorBootStrategy.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBSimulatorLaunchConfiguration.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorTerminationStrategy.h"

@implementation FBSimulatorInteraction (Lifecycle)

- (instancetype)bootSimulator
{
  return [self bootSimulator:FBSimulatorLaunchConfiguration.defaultConfiguration];
}

- (instancetype)bootSimulator:(FBSimulatorLaunchConfiguration *)configuration
{
  return [self interactWithShutdownSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [[FBSimulatorBootStrategy withConfiguration:configuration simulator:simulator] boot:error];
  }];
}

- (instancetype)shutdownSimulator
{
  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [simulator.set killSimulator:simulator error:error];
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
    pid_t parentProcessIdentifier = [simulator.processFetcher parentOf:process.processIdentifier];
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

    // Use FBProcessTerminationStrategy to do the actual process killing
    // as it has more intelligent backoff strategies and error messaging.
    NSError *innerError = nil;
    if (![[FBProcessTerminationStrategy withProcessFetcher:simulator.processFetcher logger:simulator.logger] killProcess:process error:&innerError]) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }

    // Ensure that the Simulator's launchctl knows that the process is gone
    // Killing the process should guarantee that tha Simulator knows that the process has terminated.
    [simulator.logger.debug logFormat:@"Waiting for %@ to be removed from launchctl", process.shortDescription];
    BOOL isGoneFromLaunchCtl = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout untilTrue:^ BOOL {
      return ![simulator.launchctl processIsRunningOnSimulator:process error:nil];
    }];
    if (!isGoneFromLaunchCtl) {
      return [[FBSimulatorError
        describeFormat:@"Process %@ did not get removed from launchctl", process.shortDescription]
        failBool:error];
    }
    [simulator.logger.debug logFormat:@"%@ has been removed from launchctl", process.shortDescription];

    return YES;
  }];
}

- (instancetype)killProcess:(FBProcessInfo *)process
{
  return [self signal:SIGKILL process:process];
}

@end
