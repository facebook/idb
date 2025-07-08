/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorFileCommands.h"

#import <CoreSimulator/SimDevice.h>

#import "FBSimulator.h"
#import "FBSimulatorApplicationCommands.h"
#import "FBSimulatorError.h"

@interface FBSimulatorFileCommands ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorFileCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBSimulator *)target
{
  return [[self alloc] initWithSimulator:target];
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

#pragma mark FBFileCommands Implementation

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForContainerApplication:(NSString *)bundleID
{
  return [[FBFuture
    onQueue:self.simulator.asyncQueue resolveValue:^ id<FBFileContainer> (NSError **error) {
      id<FBContainedFile> containedFile = [self containedFileForApplication:bundleID error:error];
      return [FBFileContainer fileContainerForContainedFile:containedFile];
    }]
    onQueue:self.simulator.asyncQueue contextualTeardown:^(id _, FBFutureState __) {
      // Do nothing.
      return FBFuture.empty;
    }];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForAuxillary
{
  return [FBFutureContext futureContextWithResult:[FBFileContainer fileContainerForBasePath:self.simulator.auxillaryDirectory]];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForApplicationContainers
{
  return [[FBFuture
    onQueue:self.simulator.workQueue resolveValue:^ id<FBFileContainer> (NSError **error) {
      id<FBContainedFile> containedFile = [self containedFileForApplicationContainersWithError:error];
      if (!containedFile) {
        return nil;
      }
      return [FBFileContainer fileContainerForContainedFile:containedFile];
    }]
    onQueue:self.simulator.asyncQueue contextualTeardown:^(id _, FBFutureState __) {
      // Do nothing.
      return FBFuture.empty;
    }];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForGroupContainers
{
  return [[FBFuture
    onQueue:self.simulator.workQueue resolveValue:^ id<FBFileContainer> (NSError **error) {
      id<FBContainedFile> containedFile = [self containedFileForGroupContainersWithError:error];
      if (!containedFile) {
        return nil;
      }
      return [FBFileContainer fileContainerForContainedFile:containedFile];
    }]
    onQueue:self.simulator.asyncQueue contextualTeardown:^(id _, FBFutureState __) {
      // Do nothing.
      return FBFuture.empty;
    }];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForRootFilesystem
{
  id<FBContainedFile> containedFile = [self containedFileForRootFilesystem];
  id<FBFileContainer> fileContainer = [FBFileContainer fileContainerForContainedFile:containedFile];
  return [FBFutureContext futureContextWithResult:fileContainer];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForMediaDirectory
{
  NSString *mediaDirectory = [self.simulator.dataDirectory stringByAppendingPathComponent:@"Media"];
  return [FBFutureContext futureContextWithResult:[FBFileContainer fileContainerForBasePath:mediaDirectory]];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForMDMProfiles
{
  return [[FBControlCoreError
    describeFormat:@"%@ not supported on simulators", NSStringFromSelector(_cmd)]
    failFutureContext];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForProvisioningProfiles
{
  return [[FBControlCoreError
    describeFormat:@"%@ not supported on simulators", NSStringFromSelector(_cmd)]
    failFutureContext];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForSpringboardIconLayout
{
  return [[FBControlCoreError
    describeFormat:@"%@ not supported on simulators", NSStringFromSelector(_cmd)]
    failFutureContext];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForWallpaper
{
  return [[FBControlCoreError
    describeFormat:@"%@ not supported on simulators", NSStringFromSelector(_cmd)]
    failFutureContext];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForDiskImages
{
  return [[FBControlCoreError
    describeFormat:@"%@ not supported on simulators", NSStringFromSelector(_cmd)]
    failFutureContext];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForSymbols
{
  return [[FBControlCoreError
    describeFormat:@"%@ not supported on simulators", NSStringFromSelector(_cmd)]
    failFutureContext];
}

#pragma mark FBSimulatorFileCommands Implementation

- (id<FBContainedFile>)containedFileForApplication:(NSString *)bundleID error:(NSError **)error
{
  FBInstalledApplication *installedApplication = [self.simulator installedApplicationWithBundleID:bundleID error:error];
  if (!installedApplication) {
    return nil;
  }
  NSString *container = installedApplication.dataContainer;
  if (!container) {
    return [[FBSimulatorError
      describeFormat:@"No data container present for application %@", installedApplication]
      fail:error];
  }
  return [FBFileContainer containedFileForBasePath:container];
}

- (nullable id<FBContainedFile>)containedFileForApplicationContainersWithError:(NSError **)error
{
  NSDictionary<NSString *, id> *installedApps = [self.simulator.device installedAppsWithError:error];
  if (!installedApps) {
    return nil;
  }
  NSMutableDictionary<NSString *, NSString *> *mapping = NSMutableDictionary.dictionary;
  for (NSString *bundleID in installedApps.allKeys) {
    NSDictionary<NSString *, id> *app = installedApps[bundleID];
    NSURL *dataContainer = app[@"DataContainer"];
    if (!dataContainer) {
      continue;
    }
    mapping[bundleID] = dataContainer.path;
  }
  return [FBFileContainer containedFileForPathMapping:mapping];
}

- (nullable id<FBContainedFile>)containedFileForGroupContainersWithError:(NSError **)error
{
  NSDictionary<NSString *, id> *installedApps = [self.simulator.device installedAppsWithError:error];
  if (!installedApps) {
    return nil;
  }
  NSMutableDictionary<NSString *, NSURL *> *bundleIDToURL = NSMutableDictionary.dictionary;
  for (NSString *key in installedApps.allKeys) {
    NSDictionary<NSString *, id> *app = installedApps[key];
    NSDictionary<NSString *, id> *appContainers = app[@"GroupContainers"];
    if (!appContainers) {
      continue;
    }
    [bundleIDToURL addEntriesFromDictionary:appContainers];
  }
  NSMutableDictionary<NSString *, NSString *> *pathMapping = NSMutableDictionary.dictionary;
  for (NSString *identifier in bundleIDToURL.allKeys) {
    pathMapping[identifier] = bundleIDToURL[identifier].path;
  }
  return [FBFileContainer containedFileForPathMapping:pathMapping];
}

- (id<FBContainedFile>)containedFileForRootFilesystem
{
  return [FBFileContainer containedFileForBasePath:self.simulator.dataDirectory];
}

@end
