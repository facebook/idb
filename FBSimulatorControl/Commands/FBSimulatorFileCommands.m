/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorFileCommands.h"

#import "FBSimulator.h"
#import "FBSimulatorError.h"

@interface FBSimulatorFileContainer ()

@property (nonatomic, strong, readonly) NSString *containerPath;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@implementation FBSimulatorFileContainer

- (instancetype)initWithContainerPath:(NSString *)containerPath queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _containerPath = containerPath;
  _queue = queue;

  return self;
}

#pragma mark FBFileCommands

- (FBFuture<NSNull *> *)copyPathOnHost:(NSURL *)sourcePath toDestination:(NSString *)destinationPath
{
  return [[self
    dataContainer]
    onQueue:self.queue fmap:^ FBFuture<NSNull *> * (NSString *dataContainer) {
      NSError *error;
      NSURL *basePathURL =  [NSURL fileURLWithPathComponents:@[dataContainer, destinationPath]];
      NSFileManager *fileManager = NSFileManager.defaultManager;
      NSURL *destURL = [basePathURL URLByAppendingPathComponent:sourcePath.lastPathComponent];
      if (![fileManager copyItemAtURL:sourcePath toURL:destURL error:&error]) {
        return [[[FBSimulatorError
          describeFormat:@"Could not copy from %@ to %@: %@", sourcePath, destURL, error]
          causedBy:error]
          failFuture];
      }
      return FBFuture.empty;
    }];
}

- (FBFuture<NSString *> *)copyItemInContainer:(NSString *)containerPath toDestinationOnHost:(NSString *)destinationPath
{
  __block NSString *dstPath = destinationPath;
  return [[self
    dataContainer]
    onQueue:self.queue fmap:^ FBFuture<NSString *> * (NSString *dataContainer) {
      NSString *source = [dataContainer stringByAppendingPathComponent:containerPath];
      BOOL srcIsDirecory = NO;
      if (![NSFileManager.defaultManager fileExistsAtPath:source isDirectory:&srcIsDirecory]) {
        return [[FBSimulatorError
          describeFormat:@"Source path does not exist: %@", source]
          failFuture];
      }
      if (!srcIsDirecory) {
        NSError *createDirectoryError;
        if (![NSFileManager.defaultManager createDirectoryAtPath:dstPath withIntermediateDirectories:YES attributes:nil error:&createDirectoryError]) {
          return [[[FBSimulatorError
            describeFormat:@"Could not create temporary directory: %@", createDirectoryError]
            causedBy:createDirectoryError]
            failFuture];
        }
        dstPath = [dstPath stringByAppendingPathComponent:[source lastPathComponent]];
      }
      // if it already exists at the destination path we should remove it before copying again
      if ([NSFileManager.defaultManager fileExistsAtPath:dstPath]) {
        NSError *removeError;
        if (![NSFileManager.defaultManager removeItemAtPath:dstPath error:&removeError]) {
          return [[[FBSimulatorError
            describeFormat:@"Could not remove %@", dstPath]
            causedBy:removeError]
            failFuture];
        }
      }

      NSError *copyError;
      if (![NSFileManager.defaultManager copyItemAtPath:source toPath:dstPath error:&copyError]) {
        return [[[FBSimulatorError
          describeFormat:@"Could not copy from %@ to %@: %@", source, dstPath, copyError]
          causedBy:copyError]
          failFuture];
      }
      return [FBFuture futureWithResult:destinationPath];
    }];
}

- (FBFuture<NSNull *> *)createDirectory:(NSString *)directoryPath
{
  return [[self
    dataContainer]
    onQueue:self.queue fmap:^ FBFuture<NSNull *> * (NSString *dataContainer) {
      NSError *error;
      NSString *fullPath = [dataContainer stringByAppendingPathComponent:directoryPath];
      if (![NSFileManager.defaultManager createDirectoryAtPath:fullPath withIntermediateDirectories:YES attributes:nil error:&error]) {
        return [[[FBSimulatorError
          describeFormat:@"Could not create directory %@ in container %@: %@", directoryPath, dataContainer, error]
          causedBy:error]
          failFuture];
      }
      return FBFuture.empty;
    }];
}

- (FBFuture<NSNull *> *)movePath:(NSString *)sourcePath toDestinationPath:(NSString *)destinationPath
{
  return [[self
    dataContainer]
    onQueue:self.queue fmap:^ FBFuture<NSNull *> * (NSString *dataContainer) {
      NSError *error;
      NSString *fullDestinationPath = [dataContainer stringByAppendingPathComponent:destinationPath];
      NSString *fullSourcePath = [dataContainer stringByAppendingPathComponent:sourcePath];
      if (![NSFileManager.defaultManager moveItemAtPath:fullSourcePath toPath:fullDestinationPath error:&error]) {
        return [[[FBSimulatorError
          describeFormat:@"Could not move item at %@ to %@: %@", fullSourcePath, fullDestinationPath, error]
          causedBy:error]
          failFuture];
      }
      return FBFuture.empty;
    }];
}

- (FBFuture<NSNull *> *)removePath:(NSString *)path
{
  return [[self
    dataContainer]
    onQueue:self.queue fmap:^ FBFuture<NSNull *> * (NSString *dataContainer) {
      NSError *error;
      NSString *fullPath = [dataContainer stringByAppendingPathComponent:path];
      if (![NSFileManager.defaultManager removeItemAtPath:fullPath error:&error]) {
        return [[[FBSimulatorError
          describeFormat:@"Could not remove item at path %@: %@", fullPath, error]
          causedBy:error]
          failFuture];
      }
      return FBFuture.empty;
    }];
}

- (FBFuture<NSArray<NSString *> *> *)contentsOfDirectory:(NSString *)path
{
  return [[self
    dataContainer]
    onQueue:self.queue fmap:^(NSString *dataContainer) {
      NSString *fullPath = [dataContainer stringByAppendingPathComponent:path];
      NSError *error;
      NSArray<NSString *> *contents = [NSFileManager.defaultManager contentsOfDirectoryAtPath:fullPath error:&error];
      if (!contents) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:contents];
    }];
}

- (FBFuture<NSString *> *)dataContainer
{
  return [FBFuture futureWithResult:self.containerPath];
}

@end

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
      return [[FBSimulatorFileContainer alloc] initWithContainerPath:containerPath queue:self.simulator.asyncQueue];
    }]
    onQueue:self.simulator.asyncQueue contextualTeardown:^(id _, FBFutureState __) {
      // Do nothing.
      return FBFuture.empty;
    }];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForRootFilesystem
{
  return [FBFutureContext futureContextWithResult:[[FBSimulatorFileContainer alloc] initWithContainerPath:self.simulator.dataDirectory queue:self.simulator.asyncQueue]];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForMediaDirectory
{
  return [FBFutureContext futureContextWithResult:[[FBSimulatorFileContainer alloc] initWithContainerPath:self.simulator.dataDirectory queue:self.simulator.asyncQueue]];
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

#pragma mark Private

- (FBFuture<NSString *> *)dataContainerForBundleID:(NSString *)bundleID
{
  return [[self.simulator
    installedApplicationWithBundleID:bundleID]
    onQueue:self.simulator.asyncQueue chain:^FBFuture<NSString *> *(FBFuture<FBInstalledApplication *> *future) {
      NSString *container = future.result.dataContainer;
      if (container) {
        return [FBFuture futureWithResult:container];
      }
      return [self fallbackDataContainerForBundleID:bundleID];
    }];
}

- (FBFuture<NSString *> *)fallbackDataContainerForBundleID:(NSString *)bundleID
{
  return [[self.simulator
    runningApplicationWithBundleID:bundleID]
    onQueue:self.simulator.asyncQueue fmap:^(FBProcessInfo *runningApplication) {
      NSString *homeDirectory = runningApplication.environment[@"HOME"];
      if (![NSFileManager.defaultManager fileExistsAtPath:homeDirectory]) {
        return [[FBSimulatorError
          describeFormat:@"App Home Directory does not exist at path %@", homeDirectory]
          failFuture];
      }
      return [FBFuture futureWithResult:homeDirectory];
    }];
}

@end
