/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorApplicationCommands.h"

#import <CoreSimulator/SimDevice.h>

#import <FBControlCore/FBControlCore.h>

#import "FBSimulator.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulatorError.h"
#import "FBApplicationLaunchStrategy.h"
#import "FBSimulatorSubprocessTerminationStrategy.h"

@interface FBSimulatorApplicationCommands ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorApplicationCommands

+ (instancetype)commandsWithSimulator:(FBSimulator *)simulator
{
  return [[self alloc] initWithSimulator:simulator];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  return self;
}

#pragma mark FBApplicationCommands Implementation

- (BOOL)installApplicationWithPath:(NSString *)path error:(NSError **)error
{
  NSError *innerError = nil;
  NSURL *tempDirURL = nil;

  NSString *appPath = [FBApplicationDescriptor findOrExtractApplicationAtPath:path extractPathOut:&tempDirURL error:&innerError];
  if (appPath == nil) {
    return [[FBSimulatorError causedBy:innerError] failBool:error];
  }

  BOOL installResult = [self installExtractedApplicationWithPath:appPath error:&innerError];
  if (tempDirURL != nil) {
    [NSFileManager.defaultManager removeItemAtURL:tempDirURL error:nil];
  }
  return installResult;
}
- (BOOL)uninstallApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSParameterAssert(bundleID);

  // Confirm the app is suitable to be uninstalled.
  if ([self.simulator isSystemApplicationWithBundleID:bundleID error:nil]) {
    return [[[FBSimulatorError
      describeFormat:@"Can't uninstall '%@' as it is a system Application", bundleID]
      inSimulator:self.simulator]
      failBool:error];
  }
  NSError *innerError = nil;
  if (![self.simulator installedApplicationWithBundleID:bundleID error:&innerError]) {
    return [[[[FBSimulatorError
      describeFormat:@"Can't uninstall '%@' as it isn't installed", bundleID]
      causedBy:innerError]
      inSimulator:self.simulator]
      failBool:error];
  }
  // Kill the app if it's running
  [self killApplicationWithBundleID:bundleID error:nil];
  // Then uninstall for real.
  if (![self.simulator.device uninstallApplication:bundleID withOptions:nil error:&innerError]) {
    return [[[[FBSimulatorError
      describeFormat:@"Failed to uninstall '%@'", bundleID]
      causedBy:innerError]
      inSimulator:self.simulator]
      failBool:error];
  }
  return YES;
}

- (BOOL)isApplicationInstalledWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  return [self.simulator installedApplicationWithBundleID:bundleID error:error] != nil;
}

- (BOOL)launchApplication:(FBApplicationLaunchConfiguration *)configuration error:(NSError **)error
{
  return [[FBApplicationLaunchStrategy strategyWithSimulator:self.simulator] launchApplication:configuration error:error] != nil;
}

- (BOOL)killApplicationWithBundleID:(NSString *)bundleID error:(NSError **)error
{
  NSError *innerError = nil;
  FBProcessInfo *process = [self.simulator runningApplicationWithBundleID:bundleID error:&innerError];
  if (!process) {
    return [[[[FBSimulatorError
      describeFormat:@"Could not find a running application for '%@'", bundleID]
      inSimulator:self.simulator]
      causedBy:innerError]
      failBool:error];
  }
  if (![[FBSimulatorSubprocessTerminationStrategy strategyWithSimulator:self.simulator] terminate:process error:&innerError]) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }

  return YES;
}

- (NSArray<FBApplicationDescriptor *> *)installedApplications
{
  NSMutableArray<FBApplicationDescriptor *> *applications = [NSMutableArray array];
  for (NSDictionary *appInfo in [[self.simulator.device installedAppsWithError:nil] allValues]) {
    FBApplicationDescriptor *application = [FBApplicationDescriptor applicationWithPath:appInfo[ApplicationPathKey] installTypeString:appInfo[ApplicationTypeKey] error:nil];
    if (!application) {
      continue;
    }
    [applications addObject:application];
  }
  return [applications copy];
}

- (BOOL)installExtractedApplicationWithPath:(NSString *)path error:(NSError **)error
{
  NSError *innerError = nil;

  FBApplicationDescriptor *application = [FBApplicationDescriptor userApplicationWithPath:path error:&innerError];
  if (!application) {
    return [[[FBSimulatorError
      describeFormat:@"Could not determine Application information for path %@", path]
      causedBy:innerError]
      failBool:error];
  }

  if ([self.simulator isSystemApplicationWithBundleID:application.bundleID error:nil]) {
    return YES;
  }

  NSSet<NSString *> *binaryArchitectures = application.binary.architectures;
  NSSet<NSString *> *supportedArchitectures = FBControlCoreConfigurationVariants.baseArchToCompatibleArch[self.simulator.deviceConfiguration.simulatorArchitecture];
  if (![binaryArchitectures intersectsSet:supportedArchitectures]) {
    return [[FBSimulatorError
      describeFormat:
        @"Simulator does not support any of the architectures (%@) of the executable at %@. Simulator Archs (%@)",
        [FBCollectionInformation oneLineDescriptionFromArray:binaryArchitectures.allObjects],
        application.binary.path,
        [FBCollectionInformation oneLineDescriptionFromArray:supportedArchitectures.allObjects]]
      failBool:error];
  }

  NSDictionary *options = @{
    @"CFBundleIdentifier" : application.bundleID
  };
  NSURL *appURL = [NSURL fileURLWithPath:application.path];

  if (![self.simulator.device installApplication:appURL withOptions:options error:&innerError]) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to install Application %@ with options %@", application, options]
      causedBy:innerError]
      failBool:error];
  }

  return YES;
}

#pragma mark FBSimulatorApplicationCommands

- (BOOL)installApplication:(FBApplicationDescriptor *)application error:(NSError **)error
{
  return [self installApplicationWithPath:application.path error:error];
}

- (BOOL)launchOrRelaunchApplication:(FBApplicationLaunchConfiguration *)appLaunch error:(NSError **)error
{
  NSParameterAssert(appLaunch);
  return [[FBApplicationLaunchStrategy
    strategyWithSimulator:self.simulator]
    launchOrRelaunchApplication:appLaunch error:error];
}

- (BOOL)terminateApplication:(FBApplicationDescriptor *)application error:(NSError **)error
{
  NSParameterAssert(application);
  return [self killApplicationWithBundleID:application.bundleID error:error];
}

- (BOOL)relaunchLastLaunchedApplicationWithError:(NSError **)error
{
  return [[FBApplicationLaunchStrategy
    strategyWithSimulator:self.simulator]
    relaunchLastLaunchedApplicationWithError:error];
}

- (BOOL)terminateLastLaunchedApplicationWithError:(NSError **)error
{
  return [[FBApplicationLaunchStrategy
    strategyWithSimulator:self.simulator]
    terminateLastLaunchedApplicationWithError:error];
}

@end
