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

#import "FBInteraction+Private.h"
#import "FBProcessInfo.h"
#import "FBProcessLaunchConfiguration+Helpers.h"
#import "FBProcessLaunchConfiguration.h"
#import "FBSimDeviceWrapper.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorError.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorSessionLifecycle.h"

@implementation FBSimulatorInteraction (Applications)

- (instancetype)installApplication:(FBSimulatorApplication *)application
{
  NSParameterAssert(application);

  FBSimulator *simulator = self.simulator;

  return [self interact:^ BOOL (NSError **error, id _) {
    NSError *innerError = nil;
    FBSimDeviceWrapper *wrapper = [FBSimDeviceWrapper withSimDevice:simulator.device configuration:simulator.pool.configuration processQuery:simulator.processQuery];
    if (![wrapper installApplication:[NSURL fileURLWithPath:application.path] withOptions:@{@"CFBundleIdentifier" : application.bundleID} error:error]) {
      return [[[FBSimulatorError describeFormat:@"Failed to install Application %@", application] causedBy:innerError] failBool:error];
    }

    return YES;
  }];
}

- (instancetype)launchApplication:(FBApplicationLaunchConfiguration *)appLaunch
{
  NSParameterAssert(appLaunch);

  FBSimulator *simulator = self.simulator;
  FBSimulatorSessionLifecycle *lifecycle = self.lifecycle;

  return [self interact:^ BOOL (NSError **error, id _) {
    NSError *innerError = nil;
    NSDictionary *installedApps = [simulator.device installedAppsWithError:&innerError];
    if (!installedApps) {
      return [[[FBSimulatorError describe:@"Failed to get installed apps"] inSimulator:simulator] failBool:error];
    }
    if (!installedApps[appLaunch.application.bundleID]) {
      return [[[[FBSimulatorError
        describeFormat:@"App %@ can't be launched as it isn't installed", appLaunch.application.bundleID]
        extraInfo:@"installed_apps" value:installedApps]
        inSimulator:simulator]
        failBool:error];
    }

    NSFileHandle *stdOut = nil;
    NSFileHandle *stdErr = nil;
    if (![appLaunch createFileHandlesWithStdOut:&stdOut stdErr:&stdErr error:&innerError]) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }

    NSDictionary *options = [appLaunch agentLaunchOptionsWithStdOut:stdOut stdErr:stdErr error:error];
    if (!options) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }

    FBSimDeviceWrapper *wrapper = [FBSimDeviceWrapper withSimDevice:simulator.device configuration:simulator.pool.configuration processQuery:simulator.processQuery];
    id<FBProcessInfo> process = [wrapper launchApplicationWithID:appLaunch.application.bundleID options:options error:&innerError];
    if (!process) {
      return [[[[FBSimulatorError describeFormat:@"Failed to launch application %@", appLaunch] causedBy:innerError] inSimulator:simulator] failBool:error];
    }
    [lifecycle applicationDidLaunch:appLaunch didStartWithProcessIdentifier:process.processIdentifier stdOut:stdOut stdErr:stdErr];
    return YES;

  }];
}

- (instancetype)killApplication:(FBSimulatorApplication *)application
{
  return [self signal:SIGKILL application:application];
}

- (instancetype)signal:(int)signo application:(FBSimulatorApplication *)application
{
  NSParameterAssert(application);

  FBSimulator *simulator = self.simulator;
  FBSimulatorSessionLifecycle *lifecycle = self.lifecycle;

  return [self binary:application.binary interact:^ BOOL (id<FBProcessInfo> process, NSError **error) {
    [lifecycle applicationWillTerminate:application];
    int returnCode = kill(process.processIdentifier, signo);
    if (returnCode != 0) {
      return [[[FBSimulatorError describeFormat:@"SIGKILL of Application %@ of PID %d failed", application, process.processIdentifier] inSimulator:simulator] failBool:error];
    }
    return YES;
  }];
}

@end
