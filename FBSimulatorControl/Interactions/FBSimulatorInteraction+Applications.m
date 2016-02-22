/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction+Applications.h"

#import <CoreSimulator/SimDevice.h>

#import "FBProcessInfo.h"
#import "FBProcessLaunchConfiguration+Helpers.h"
#import "FBProcessLaunchConfiguration.h"
#import "FBProcessQuery+Helpers.h"
#import "FBSimDeviceWrapper.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorControlGlobalConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorHistory+Queries.h"
#import "FBSimulatorInteraction+Lifecycle.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBSimulatorLaunchCtl.h"
#import "FBSimulatorPool.h"
#import "NSRunLoop+SimulatorControlAdditions.h"

@implementation FBSimulatorInteraction (Applications)

- (instancetype)installApplication:(FBSimulatorApplication *)application
{
  NSParameterAssert(application);

  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    if ([simulator isSystemApplicationWithBundleID:application.bundleID error:nil]) {
      return YES;
    }

    NSError *innerError = nil;
    NSDictionary *options = @{
      @"CFBundleIdentifier" : application.bundleID
    };
    NSURL *appURL = [NSURL fileURLWithPath:application.path];

    if (![simulator.simDeviceWrapper installApplication:appURL withOptions:options error:&innerError]) {
      return [[[FBSimulatorError
        describeFormat:@"Failed to install Application %@ with options %@", application, options]
        causedBy:innerError]
        failBool:error];
    }

    return YES;
  }];
}

- (instancetype)launchApplication:(FBApplicationLaunchConfiguration *)appLaunch
{
  NSParameterAssert(appLaunch);

  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    NSError *innerError = nil;
    FBSimulatorApplication *application = [simulator installedApplicationWithBundleID:appLaunch.bundleID error:&innerError];
    if (!application) {
      return [[[[FBSimulatorError
        describeFormat:@"App %@ can't be launched as it isn't installed", appLaunch.bundleID]
        causedBy:innerError]
        inSimulator:simulator]
        failBool:error];
    }

    // This check confirms that if there's a currently running process for the given Bundle ID it doesn't match one that has been recently launched.
    // Since the Background Modes of a Simulator can cause an Application to be launched independently of our usage of CoreSimulator,
    // it's possible that application processes will come to life before `launchApplication` is called, if it has been previously killed.
    FBProcessInfo *process = [simulator runningApplicationWithBundleID:appLaunch.bundleID error:&innerError];
    if (process && [simulator.history.launchedApplicationProcesses containsObject:process]) {
      return [[[[FBSimulatorError
        describeFormat:@"App %@ can't be launched as is running (%@)", appLaunch.bundleID, process.shortDescription]
        causedBy:innerError]
        inSimulator:simulator]
        failBool:error];
    }

    NSFileHandle *stdOut = nil;
    NSFileHandle *stdErr = nil;
    if (![appLaunch createFileHandlesWithStdOut:&stdOut stdErr:&stdErr error:&innerError]) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }

    NSDictionary *options = [appLaunch simDeviceLaunchOptionsWithStdOut:stdOut stdErr:stdErr];
    if (!options) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }

    process = [simulator.simDeviceWrapper launchApplicationWithID:appLaunch.bundleID options:options error:&innerError];
    if (!process) {
      return [[[[FBSimulatorError describeFormat:@"Failed to launch application %@", appLaunch] causedBy:innerError] inSimulator:simulator] failBool:error];
    }
    [simulator.eventSink applicationDidLaunch:appLaunch didStart:process stdOut:stdOut stdErr:stdErr];
    return YES;
  }];
}

- (instancetype)launchOrRelaunchApplication:(FBApplicationLaunchConfiguration *)appLaunch
{
  NSParameterAssert(appLaunch);

  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    // Kill the Application if it exists. Don't bother killing the process if it doesn't exist
    NSError *innerError = nil;
    FBProcessInfo *process = [simulator runningApplicationWithBundleID:appLaunch.bundleID error:&innerError];
    if (process) {
      if (![[simulator.interact killProcess:process] perform:&innerError]) {
        return [FBSimulatorError failBoolWithError:innerError errorOut:error];
      }
    }

    // Perform the launch usin the launch config
    if (![[simulator.interact launchApplication:appLaunch] perform:&innerError]) {
      return [[[[FBSimulatorError
        describeFormat:@"Failed to re-launch %@", appLaunch]
        inSimulator:simulator]
        causedBy:innerError]
        failBool:error];
    }
    return YES;
  }];
}

- (instancetype)terminateApplication:(FBSimulatorApplication *)application
{
  NSParameterAssert(application);
  return [self terminateApplicationWithBundleID:application.bundleID];
}

- (instancetype)terminateApplicationWithBundleID:(NSString *)bundleID
{
  NSParameterAssert(bundleID);

  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    NSError *innerError = nil;
    FBProcessInfo *process = [simulator runningApplicationWithBundleID:bundleID error:&innerError];
    if (!process) {
      return [[[[FBSimulatorError
        describeFormat:@"Could not find a running application for '%@'", bundleID]
        inSimulator:simulator]
        causedBy:innerError]
        failBool:error];
    }
    if (![[simulator.interact killProcess:process] perform:&innerError]) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }
    return YES;
  }];
}

- (instancetype)relaunchLastLaunchedApplication
{
  return [self interactWithLastLaunchedApplicationProcess:^ BOOL (NSError **error, FBSimulator *simulator, FBProcessInfo *process) {
    // Obtain the Launch Config for the process.
    FBApplicationLaunchConfiguration *launchConfig = simulator.history.processLaunchConfigurations[process];
    if (!process) {
      return [[[FBSimulatorError
        describe:@"Cannot re-launch an Application until one has been launched; there's no prior process launch config"]
        inSimulator:simulator]
        failBool:error];
    }

    return [[simulator.interact launchOrRelaunchApplication:launchConfig] perform:error];
  }];
}

- (instancetype)terminateLastLaunchedApplication
{
  return [self interactWithLastLaunchedApplicationProcess:^ BOOL (NSError **error, FBSimulator *simulator, FBProcessInfo *process) {
    // Kill the Application Process
    NSError *innerError = nil;
    if (![[simulator.interact killProcess:process] perform:&innerError]) {
      return [[[[FBSimulatorError
        describeFormat:@"Failed to terminate app %@", process.shortDescription]
        causedBy:innerError]
        inSimulator:simulator]
        failBool:error];
    }
    return YES;
  }];
}

#pragma mark Private

- (instancetype)interactWithLastLaunchedApplicationProcess:(BOOL (^)(NSError **error, FBSimulator *simulator, FBProcessInfo *process))block
{
  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    // Obtain Application Launch info for the last launch.
    FBProcessInfo *process = simulator.history.lastLaunchedApplicationProcess;
    if (!process) {
      return [[[FBSimulatorError
        describe:@"Cannot re-launch an find the last-launched process"]
        inSimulator:simulator]
        failBool:error];
    }

    return block(error, simulator, process);
  }];
}

@end
