/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorFileCommands.h"

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
  return [[[self
    dataContainerForBundleID:bundleID]
    onQueue:self.simulator.asyncQueue map:^(NSString *containerPath) {
      return [FBFileContainer fileContainerForBasePath:containerPath];
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
  return [[[FBSimulatorApplicationCommands
    applicationContainerToPathMappingForSimulator:self.simulator]
    onQueue:self.simulator.asyncQueue map:^(NSDictionary<NSString *, NSURL *> *pathMappingURLs) {
      NSMutableDictionary<NSString *, NSString *> *pathMapping = NSMutableDictionary.dictionary;
      for (NSString *identifier in pathMappingURLs.allKeys) {
        pathMapping[identifier] = pathMappingURLs[identifier].path;
      }
      return [FBFileContainer fileContainerForPathMapping:pathMapping];
    }]
    onQueue:self.simulator.asyncQueue contextualTeardown:^(id _, FBFutureState __) {
      // Do nothing.
      return FBFuture.empty;
    }];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForGroupContainers
{
  return [[[FBSimulatorApplicationCommands
    groupContainerToPathMappingForSimulator:self.simulator]
    onQueue:self.simulator.asyncQueue map:^(NSDictionary<NSString *, NSURL *> *pathMappingURLs) {
      NSMutableDictionary<NSString *, NSString *> *pathMapping = NSMutableDictionary.dictionary;
      for (NSString *identifier in pathMappingURLs.allKeys) {
        pathMapping[identifier] = pathMappingURLs[identifier].path;
      }
      return [FBFileContainer fileContainerForPathMapping:pathMapping];
    }]
    onQueue:self.simulator.asyncQueue contextualTeardown:^(id _, FBFutureState __) {
      // Do nothing.
      return FBFuture.empty;
    }];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForRootFilesystem
{
  return [FBFutureContext futureContextWithResult:[FBFileContainer fileContainerForBasePath:self.simulator.dataDirectory]];
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

#pragma mark Private

- (FBFuture<NSString *> *)dataContainerForBundleID:(NSString *)bundleID
{
  return [[self.simulator
    installedApplicationWithBundleID:bundleID]
    onQueue:self.simulator.asyncQueue fmap:^ FBFuture<NSString *> * (FBInstalledApplication *installedApplication) {
      NSString *container = installedApplication.dataContainer;
      if (!container) {
        return [[FBSimulatorError
          describeFormat:@"No data container present for application %@", installedApplication]
          failFuture];
      }
      return [FBFuture futureWithResult:container];
    }];
}

@end
