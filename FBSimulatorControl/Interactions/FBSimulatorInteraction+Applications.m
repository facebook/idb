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

#import <FBControlCore/FBControlCore.h>

#import "FBApplicationLaunchStrategy.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBApplicationLaunchStrategy.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorHistory+Queries.h"
#import "FBSimulatorInteraction+Lifecycle.h"
#import "FBSimulatorInteraction+Private.h"
#import "FBSimulatorLaunchCtl.h"
#import "FBSimulatorPool.h"

@implementation FBSimulatorInteraction (Applications)

- (instancetype)installApplication:(FBApplicationDescriptor *)application
{
  NSParameterAssert(application);

  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [simulator installApplicationWithPath:application.path error:error];
  }];
}

- (instancetype)uninstallApplicationWithBundleID:(NSString *)bundleID
{
  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [[FBApplicationLaunchStrategy withSimulator:simulator] uninstallApplication:bundleID error:error];
  }];
}

- (instancetype)launchApplication:(FBApplicationLaunchConfiguration *)appLaunch
{
  NSParameterAssert(appLaunch);

  return [self chainNext:[FBCommandInteractions launchApplication:appLaunch command:self.simulator]];
}

- (instancetype)launchOrRelaunchApplication:(FBApplicationLaunchConfiguration *)appLaunch
{
  NSParameterAssert(appLaunch);

  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [[FBApplicationLaunchStrategy withSimulator:simulator] launchOrRelaunchApplication:appLaunch error:error];
  }];
}

- (instancetype)terminateApplication:(FBApplicationDescriptor *)application
{
  NSParameterAssert(application);
  return [self terminateApplicationWithBundleID:application.bundleID];
}

- (instancetype)terminateApplicationWithBundleID:(NSString *)bundleID
{
  NSParameterAssert(bundleID);

  return [self chainNext:[FBCommandInteractions killApplicationWithBundleID:bundleID command:self.simulator]];
}

- (instancetype)relaunchLastLaunchedApplication
{
  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [[FBApplicationLaunchStrategy withSimulator:simulator] relaunchLastLaunchedApplicationWithError:error];
  }];
}

- (instancetype)terminateLastLaunchedApplication
{
  return [self interactWithBootedSimulator:^ BOOL (NSError **error, FBSimulator *simulator) {
    return [[FBApplicationLaunchStrategy withSimulator:simulator] terminateLastLaunchedApplicationWithError:error];
  }];
}

@end
