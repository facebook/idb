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
#import <CoreSimulator/SimDeviceSet.h>

#import <FBControlCore/FBControlCore.h>

#import "FBProcessFetcher+Simulators.h"
#import "FBSimDeviceWrapper.h"
#import "FBSimulator+Private.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorError.h"
#import "FBSimulatorHistory+Queries.h"
#import "FBSimulatorInteraction.h"
#import "FBSimulatorLaunchCtl.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorSet.h"

@implementation FBSimulator (Helpers)

#pragma mark Properties

- (FBSimulatorInteraction *)interact
{
  return [FBSimulatorInteraction withSimulator:self];
}

- (FBSimDeviceWrapper *)simDeviceWrapper
{
  return [FBSimDeviceWrapper withSimulator:self configuration:self.set.configuration processFetcher:self.processFetcher];
}

- (FBSimulatorLaunchCtl *)launchctl
{
  return [FBSimulatorLaunchCtl withSimulator:self];
}

- (NSString *)deviceSetPath
{
  return self.set.deviceSet.setPath;
}

- (NSArray<FBProcessInfo *> *)launchdSimSubprocesses
{
  FBProcessInfo *launchdSim = self.launchdSimProcess;
  if (!launchdSim) {
    return @[];
  }
  return [self.processFetcher subprocessesOf:launchdSim.processIdentifier];
}

- (NSArray<FBSimulatorApplication *> *)installedApplications
{
  NSMutableArray<FBSimulatorApplication *> *applications = [NSMutableArray array];
  for (NSDictionary *appInfo in [[self.device installedAppsWithError:nil] allValues]) {
    FBSimulatorApplication *application = [FBSimulatorApplication applicationWithPath:appInfo[@"Path"] error:nil];
    if (!application) {
      continue;
    }
    [applications addObject:application];
  }
  return [applications copy];
}

#pragma mark Methods

+ (FBSimulatorState)simulatorStateFromStateString:(NSString *)stateString
{
  return FBSimulatorStateFromStateString(stateString);
}

+ (NSString *)stateStringFromSimulatorState:(FBSimulatorState)state
{
  return FBSimulatorStateStringFromState(state);
}

- (BOOL)waitOnState:(FBSimulatorState)state
{
  return [self waitOnState:state timeout:FBControlCoreGlobalConfiguration.regularTimeout];
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

- (BOOL)eraseWithError:(NSError **)error
{
  return [self.set eraseSimulator:self error:error];
}

- (FBSimulatorApplication *)installedApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSParameterAssert(bundleID);

  NSError *innerError = nil;
  NSDictionary *appInfo = [self appInfo:bundleID error:&innerError];
  if (!appInfo) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
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

- (BOOL)isSystemApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSParameterAssert(bundleID);

  NSError *innerError = nil;
  NSDictionary *appInfo = [self appInfo:bundleID error:&innerError];
  if (!appInfo) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }

  return [appInfo[@"ApplicationType"] isEqualToString:@"System"];
}

- (NSString *)homeDirectoryOfApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSParameterAssert(bundleID);

  NSError *innerError = nil;
  FBProcessInfo *runningApplication = [self runningApplicationWithBundleID:bundleID error:&innerError];
  if (!runningApplication) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }
  NSString *homeDirectory = runningApplication.environment[@"HOME"];
  if (![NSFileManager.defaultManager fileExistsAtPath:homeDirectory]) {
    return [[FBSimulatorError describeFormat:@"App Home Directory does not exist at path %@", homeDirectory] fail:error];
  }

  return homeDirectory;
}

- (FBProcessInfo *)runningApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSParameterAssert(bundleID);

  NSError *innerError = nil;
  FBSimulatorApplication *application = [self installedApplicationWithBundleID:bundleID error:&innerError];
  if (!application) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  return [[[self
    launchdSimSubprocesses]
    filteredArrayUsingPredicate:[FBSimulator predicateForApplicationProcessOfApplication:application]]
    firstObject];
}

- (NSSet *)requiredProcessNamesToVerifyBooted
{
  if (self.productFamily == FBControlCoreProductFamilyiPhone || self.productFamily == FBControlCoreProductFamilyiPad) {
    return [NSSet setWithArray:@[
       @"SpringBoard",
       @"SimulatorBridge",
       @"backboardd",
       @"installd",
    ]];
  }
  if (self.productFamily == FBControlCoreProductFamilyAppleWatch || self.productFamily == FBControlCoreProductFamilyAppleTV) {
    return [NSSet setWithArray:@[
       @"backboardd",
       @"networkd",
       @"mobileassetd",
       @"UserEventAgent",
    ]];
  }
  return [NSSet set];
}

#pragma mark Private

- (NSDictionary *)appInfo:(NSString *)bundleID error:(NSError **)error
{
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
  return appInfo;
}

+ (NSPredicate *)predicateForApplicationProcessOfApplication:(FBSimulatorApplication *)application
{
  NSPredicate *launchPathPredicate = [FBProcessFetcher processesWithLaunchPath:application.binary.path];
  NSPredicate *environmentPredicate = [NSPredicate predicateWithBlock:^ BOOL (NSProcessInfo *processInfo, NSDictionary *_) {
    return [processInfo.environment[@"XPC_SERVICE_NAME"] containsString:application.bundleID];
  }];

  return [NSCompoundPredicate orPredicateWithSubpredicates:@[
    launchPathPredicate,
    environmentPredicate
  ]];
}

@end
