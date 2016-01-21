/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulator+Helpers.h"

#import <CoreSimulator/SimDevice.h>

#import "FBCollectionDescriptions.h"
#import "FBProcessInfo.h"
#import "FBProcessQuery.h"
#import "FBSimDeviceWrapper.h"
#import "FBSimulator+Private.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorControlGlobalConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorHistory+Queries.h"
#import "FBSimulatorInteraction.h"
#import "FBSimulatorLaunchCtl.h"
#import "FBSimulatorPool.h"
#import "NSRunLoop+SimulatorControlAdditions.h"

@implementation FBSimulator (Helpers)

- (FBSimulatorInteraction *)interact
{
  return [FBSimulatorInteraction withSimulator:self];
}

+ (FBSimulatorState)simulatorStateFromStateString:(NSString *)stateString
{
  stateString = [[stateString lowercaseString] stringByReplacingOccurrencesOfString:@"-" withString:@" "];
  if ([stateString isEqualToString:@"creating"]) {
    return FBSimulatorStateCreating;
  }
  if ([stateString isEqualToString:@"shutdown"]) {
    return FBSimulatorStateShutdown;
  }
  if ([stateString isEqualToString:@"booting"]) {
    return FBSimulatorStateBooting;
  }
  if ([stateString isEqualToString:@"booted"]) {
    return FBSimulatorStateBooted;
  }
  if ([stateString isEqualToString:@"creating"]) {
    return FBSimulatorStateCreating;
  }
  if ([stateString isEqualToString:@"shutting down"]) {
    return FBSimulatorStateShuttingDown;
  }
  return FBSimulatorStateUnknown;
}

+ (NSString *)stateStringFromSimulatorState:(FBSimulatorState)state
{
  switch (state) {
    case FBSimulatorStateCreating:
      return @"Creating";
    case FBSimulatorStateShutdown:
      return @"Shutdown";
    case FBSimulatorStateBooting:
      return @"Booting";
    case FBSimulatorStateBooted:
      return @"Booted";
    case FBSimulatorStateShuttingDown:
      return @"Shutting Down";
    default:
      return @"Unknown";
  }
}

- (BOOL)waitOnState:(FBSimulatorState)state
{
  return [self waitOnState:state timeout:FBSimulatorControlGlobalConfiguration.regularTimeout];
}

- (BOOL)waitOnState:(FBSimulatorState)state timeout:(NSTimeInterval)timeout
{
  return [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilTrue:^ BOOL {
    return self.state == state;
  }];
}

- (BOOL)waitOnState:(FBSimulatorState)state withError:(NSError **)error
{
  if (![self waitOnState:state]) {
    return [[[FBSimulatorError
      describeFormat:@"Simulator was not in expected %@ state, got %@", [FBSimulator stateStringFromSimulatorState:state], self.stateString]
      inSimulator:self]
      failBool:error];
  }
  return YES;
}

- (BOOL)freeFromPoolWithError:(NSError **)error
{
  if (!self.pool) {
    return [FBSimulatorError failBoolWithErrorMessage:@"Cannot free from pool as there is no pool associated" errorOut:error];
  }
  if (!self.isAllocated) {
    return [FBSimulatorError failBoolWithErrorMessage:@"Cannot free from pool as this Simulator has not been allocated" errorOut:error];
  }
  return [self.pool freeSimulator:self error:error];
}

- (NSString *)pathForStorage:(NSString *)key ofExtension:(NSString *)extension
{
  NSString *filename = [NSString stringWithFormat:@"%@_storage", self.udid];
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
  path = extension ? [path stringByAppendingPathExtension:extension] : path;

  BOOL success = [NSFileManager.defaultManager createFileAtPath:path contents:NSData.data attributes:nil];
  NSAssert(success, @"Cannot create a path for storage at %@", path);
  return path;
}

- (BOOL)eraseWithError:(NSError **)error
{
  NSError *innerError = nil;
  if (![self.device eraseContentsAndSettingsWithError:&innerError]) {
    return [[[[FBSimulatorError describeFormat:@"Failed to Erase Contents and Settings %@", self] causedBy:innerError] inSimulator:self] failBool:error];
  }
  return YES;
}

- (FBSimulatorApplication *)installedApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSParameterAssert(bundleID);

  NSError *innerError = nil;
  NSDictionary *appInfo = [self.device propertiesOfApplication:bundleID error:&innerError];
  if (!appInfo) {
    NSDictionary *installedApps = [self.device installedAppsWithError:nil];
    return [[[[[FBSimulatorError
      describeFormat:@"Application with bundle ID '%@' is not installed", bundleID]
      extraInfo:@"installed_apps" value:installedApps.allKeys]
      inSimulator:self]
      causedBy:innerError]
      fail:error];
  }
  NSString *appPath = appInfo[@"Path"];
  FBSimulatorApplication *application = [FBSimulatorApplication applicationWithPath:appPath error:&innerError];
  if (!application) {
    return [[[[FBSimulatorError
      describeFormat:@"Failed to get App Path of %@ at %@", bundleID, appPath]
      inSimulator:self]
      causedBy:innerError]
      fail:error];
  }
  return application;
}

- (FBSimDeviceWrapper *)simDeviceWrapper
{
  return [FBSimDeviceWrapper withSimulator:self configuration:self.pool.configuration processQuery:self.processQuery];
}

- (FBSimulatorLaunchCtl *)launchctl
{
  return [FBSimulatorLaunchCtl withSimulator:self];
}

- (NSArray *)launchdSimSubprocesses
{
  FBProcessInfo *launchdSim = self.launchdSimProcess;
  if (!launchdSim) {
    return @[];
  }
  return [self.processQuery subprocessesOf:launchdSim.processIdentifier];
}

- (NSSet *)requiredProcessNamesToVerifyBooted
{
  if (self.productFamily == FBSimulatorProductFamilyiPhone || self.productFamily == FBSimulatorProductFamilyiPad) {
    return [NSSet setWithArray:@[
       @"SpringBoard",
       @"SimulatorBridge",
       @"backboardd",
       @"installd",
    ]];
  }
  if (self.productFamily == FBSimulatorProductFamilyAppleWatch || self.productFamily == FBSimulatorProductFamilyAppleTV) {
    return [NSSet setWithArray:@[
       @"backboardd",
       @"networkd",
       @"mobileassetd",
       @"UserEventAgent",
    ]];
  }
  return [NSSet set];
}

- (NSString *)homeDirectoryOfLastLaunchedApplication
{
  FBProcessInfo* processInfo = [self.history lastLaunchedApplicationProcess];
  NSDictionary* environment = processInfo.environment;
  return environment[@"HOME"];
}

@end
