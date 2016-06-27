/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction+Applications.h"

#import <FBControlCore/FBControlCore.h>

#import "FBProcessLaunchConfiguration+Helpers.h"
#import "FBApplicationLaunchStrategy.h"
#import "FBProcessLaunchConfiguration.h"
#import "FBSimDeviceWrapper.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorError.h"
#import "FBApplicationLaunchStrategy.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorHistory+Queries.h"
#import "FBSimulatorInteraction+Lifecycle.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBSimulatorLaunchCtl.h"
#import "FBSimulatorPool.h"

@implementation FBSimulatorInteraction (Applications)

- (instancetype)installApplication:(FBSimulatorApplication *)application
{
  NSParameterAssert(application);

  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [simulator installApplicationWithPath:application.path error:error];
  }];
}

- (instancetype)uninstallApplicationWithBundleID:(NSString *)bundleID
{
  NSParameterAssert(bundleID);

  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    // Confirm the app is suitable to be uninstalled.
    if ([simulator isSystemApplicationWithBundleID:bundleID error:nil]) {
      return [[[FBSimulatorError
        describeFormat:@"Can't uninstall '%@' as it is a system Application", bundleID]
        inSimulator:simulator]
        failBool:error];
    }
    NSError *innerError = nil;
    if (![simulator installedApplicationWithBundleID:bundleID error:&innerError]) {
      return [[[[FBSimulatorError
        describeFormat:@"Can't uninstall '%@' as it isn't installed", bundleID]
        causedBy:innerError]
        inSimulator:simulator]
        failBool:error];
    }
    // Kill the app if it's running
    [[simulator.interact terminateApplicationWithBundleID:bundleID] perform:nil];
    // Then uninstall for real.
    if (![simulator.simDeviceWrapper uninstallApplication:bundleID withOptions:nil error:&innerError]) {
      return [[[[FBSimulatorError
        describeFormat:@"Failed to uninstall '%@'", bundleID]
        causedBy:innerError]
        inSimulator:simulator]
        failBool:error];
    }
    return YES;
  }];
}

- (instancetype)launchApplication:(FBApplicationLaunchConfiguration *)appLaunch
{
  NSParameterAssert(appLaunch);

  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [[FBApplicationLaunchStrategy withSimulator:simulator]
      launchApplication:appLaunch error:error] != nil;
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
