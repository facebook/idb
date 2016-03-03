/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction+Lifecycle.h"

#import <mach/exc.h>
#import <mach/mig.h>

#import <Cocoa/Cocoa.h>

#import <CoreSimulator/SimDevice.h>

#import <SimulatorKit/SimDeviceFramebufferService.h>

#import "FBCollectionDescriptions.h"
#import "FBProcessInfo.h"
#import "FBProcessLaunchConfiguration.h"
#import "FBProcessQuery+Simulators.h"
#import "FBProcessTerminationStrategy.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControl.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorControlGlobalConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorFramebuffer.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBSimulatorLaunchConfiguration+Helpers.h"
#import "FBSimulatorLaunchConfiguration.h"
#import "FBSimulatorLogger.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorTerminationStrategy.h"
#import "FBTaskExecutor.h"

@implementation FBSimulatorInteraction (Lifecycle)

- (instancetype)bootSimulator
{
  return [self bootSimulator:FBSimulatorLaunchConfiguration.defaultConfiguration];
}

- (instancetype)bootSimulator:(FBSimulatorLaunchConfiguration *)configuration
{
  return [self interactWithShutdownSimulator:^ BOOL (id _, NSError **error, FBSimulator *simulator) {
    BOOL useDirectLaunch = (configuration.options & FBSimulatorLaunchOptionsEnableDirectLaunch) == FBSimulatorLaunchOptionsEnableDirectLaunch;
    if (useDirectLaunch) {
      return [FBSimulatorInteraction launchSimulatorDirectly:simulator configuration:configuration error:error];
    }
    return [FBSimulatorInteraction launchSimulatorFromXcodeApplication:simulator configuration:configuration error:error];
  }];
}

- (instancetype)shutdownSimulator
{
  return [self interactWithBootedSimulator:^ BOOL (id _, NSError **error, FBSimulator *simulator) {
    return [simulator.set killSimulator:simulator error:error];
  }];
}

- (instancetype)openURL:(NSURL *)url
{
  NSParameterAssert(url);

  return [self interactWithBootedSimulator:^ BOOL (id _, NSError **error, FBSimulator *simulator) {
    NSError *innerError = nil;
    if (![simulator.device openURL:url error:&innerError]) {
      NSString *description = [NSString stringWithFormat:@"Failed to open URL %@ on simulator %@", url, simulator];
      return [FBSimulatorError failBoolWithError:innerError description:description errorOut:error];
    }
    return YES;
  }];
}

#pragma mark Private

+ (BOOL)launchSimulatorDirectly:(FBSimulator *)simulator configuration:(FBSimulatorLaunchConfiguration *)configuration error:(NSError **)error
{
  NSError *innerError = nil;
  FBSimulatorBridge *bridge = [FBSimulatorBridge bootSimulator:simulator withConfiguration:configuration andAttachBridgeWithError:&innerError];
  if (!bridge) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }

  // Expect the launchd_sim process to be updated.
  if (![self launchdSimWithAllRequiredProcessesForSimulator:simulator error:&innerError]) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }
  
  return YES;
}

+ (BOOL)launchSimulatorFromXcodeApplication:(FBSimulator *)simulator configuration:(FBSimulatorLaunchConfiguration *)configuration error:(NSError **)error
{
  // Fetch the Boot Arguments & Environment
  NSError *innerError = nil;
  NSArray *arguments = [configuration xcodeSimulatorApplicationArgumentsForSimulator:simulator error:&innerError];
  if (!arguments) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to create boot args for Configuration %@", configuration]
      causedBy:innerError]
      failBool:error];
  }
  NSDictionary *environment = @{ FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID : simulator.udid };

  // Launch the Simulator.app Process.
  BOOL useWorkspace = (configuration.options & FBSimulatorLaunchOptionsUseNSWorkspace) == FBSimulatorLaunchOptionsUseNSWorkspace;
  if (useWorkspace) {
    [self launchSimulatorApplicationViaWorkspace:simulator arguments:arguments environment:environment error:error];
  } else {
    [self launchSimulatorApplicationViaSubprocess:simulator arguments:arguments environment:environment error:error];
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
  FBProcessInfo *containerApplication = [simulator.processQuery simulatorApplicationProcessForSimDevice:simulator.device];
  if (!containerApplication) {
    return [[[FBSimulatorError
      describe:@"Could not obtain process info for container application"]
      inSimulator:simulator]
      failBool:error];
  }
  [simulator.eventSink containerApplicationDidLaunch:containerApplication];

  // Expect the launchd_sim process to be updated.
  if (![self launchdSimWithAllRequiredProcessesForSimulator:simulator error:error]) {
    return NO;
  }

  return YES;
}

+ (BOOL)launchSimulatorApplicationViaSubprocess:(FBSimulator *)simulator arguments:(NSArray *)arguments environment:(NSDictionary *)environment error:(NSError **)error
{
  // Construct and start the task.
  id<FBTask> task = [[[[[FBTaskExecutor.sharedInstance
    withLaunchPath:FBSimulatorApplication.xcodeSimulator.binary.path]
    withArguments:arguments]
    withEnvironmentAdditions:environment]
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
  return YES;
}

+ (BOOL)launchSimulatorApplicationViaWorkspace:(FBSimulator *)simulator arguments:(NSArray *)arguments environment:(NSDictionary *)environment error:(NSError **)error
{
  // The NSWorkspace API allows for arguments & environment to be provided to the launched application
  // Additionally, multiple Apps of the same application can be launched with the NSWorkspaceLaunchNewInstance option.
  NSURL *applicationURL = [NSURL fileURLWithPath:FBSimulatorApplication.xcodeSimulator.path];
  NSDictionary *appLaunchConfiguration = @{
    NSWorkspaceLaunchConfigurationArguments : arguments,
    NSWorkspaceLaunchConfigurationEnvironment : environment,
  };

  NSError *innerError = nil;
  NSRunningApplication *application = [NSWorkspace.sharedWorkspace
    launchApplicationAtURL:applicationURL
    options:NSWorkspaceLaunchDefault | NSWorkspaceLaunchNewInstance | NSWorkspaceLaunchWithoutActivation
    configuration:appLaunchConfiguration
    error:&innerError];

  if (!application) {
    return [[[[FBSimulatorError
      describeFormat:@"Failed to launch simulator application %@ with configuration %@", applicationURL, appLaunchConfiguration]
      inSimulator:simulator]
      causedBy:innerError]
      failBool:error];
  }
  return YES;
}

+ (FBProcessInfo *)launchdSimWithAllRequiredProcessesForSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  FBProcessQuery *processQuery = simulator.processQuery;
  FBProcessInfo *launchdSimProcess = [processQuery launchdSimProcessForSimDevice:simulator.device];
  if (!launchdSimProcess) {
    return [[[FBSimulatorError
      describe:@"Could not obtain process info for launchd_sim process"]
      inSimulator:simulator]
      fail:error];
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
      fail:error];
  }

  return launchdSimProcess;
}

@end
