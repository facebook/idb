/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorFileCommands.h"

#import "FBSimulator.h"
#import "FBSimulatorError.h"

@interface FBSimulatorFileContainer : NSObject <FBFileContainer>

@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@implementation FBSimulatorFileContainer

- (instancetype)initWithQueue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }
  
  _queue = queue;

  return self;
}

#pragma mark FBFileCommands

- (FBFuture<NSNull *> *)copyFromHost:(NSURL *)sourcePath toContainer:(NSString *)destinationPath
{
  return [[self
    mappedPath:destinationPath]
    onQueue:self.queue fmap:^ FBFuture<NSNull *> * (NSString *mappedPath) {
      NSError *error;
      NSURL *basePathURL = [NSURL fileURLWithPath:mappedPath];
      NSFileManager *fileManager = NSFileManager.defaultManager;
      NSURL *destURL = [basePathURL URLByAppendingPathComponent:sourcePath.lastPathComponent];
      // Attempt to delete first to overwrite
      [fileManager removeItemAtURL:destURL error:nil];
      if (![fileManager copyItemAtURL:sourcePath toURL:destURL error:&error]) {
        return [[[FBSimulatorError
          describeFormat:@"Could not copy from %@ to %@: %@", sourcePath, destURL, error]
          causedBy:error]
          failFuture];
      }
      return FBFuture.empty;
    }];
}

- (FBFuture<NSString *> *)copyFromContainer:(NSString *)containerPath toHost:(NSString *)destinationPath
{
  __block NSString *dstPath = destinationPath;
  return [[self
    mappedPath:containerPath]
    onQueue:self.queue fmap:^ FBFuture<NSString *> * (NSString *source) {
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

- (FBFuture<FBFuture<NSNull *> *> *)tail:(NSString *)containerPath toConsumer:(id<FBDataConsumer>)consumer
{
  return [[[self
    mappedPath:containerPath]
    onQueue:self.queue fmap:^(NSString *fullSourcePath) {
      return [[[[FBTaskBuilder
        withLaunchPath:@"/usr/bin/tail"]
        withArguments:@[@"-c+1", @"-f", fullSourcePath]]
        withStdOutConsumer:consumer]
        start];
    }]
    onQueue:self.queue map:^(FBTask *task) {
      return [task.statLoc
        onQueue:self.queue respondToCancellation:^{
          return [task sendSignal:SIGTERM backingOffToKillWithTimeout:1 logger:nil];
        }];
    }];
}

- (FBFuture<NSNull *> *)createDirectory:(NSString *)directoryPath
{
  return [[self
    mappedPath:directoryPath]
    onQueue:self.queue fmap:^ FBFuture<NSNull *> * (NSString *fullPath) {
      NSError *error;
      if (![NSFileManager.defaultManager createDirectoryAtPath:fullPath withIntermediateDirectories:YES attributes:nil error:&error]) {
        return [[[FBSimulatorError
          describeFormat:@"Could not create directory %@ at container %@: %@", directoryPath, fullPath, error]
          causedBy:error]
          failFuture];
      }
      return FBFuture.empty;
    }];
}

- (FBFuture<NSNull *> *)moveFrom:(NSString *)sourcePath to:(NSString *)destinationPath
{
  return [[FBFuture
    futureWithFutures:@[
      [self mappedPath:sourcePath],
      [self mappedPath:destinationPath],
    ]]
    onQueue:self.queue fmap:^ FBFuture<NSNull *> * (NSArray<NSString *> *mappedPaths) {
      NSString *fullSourcePath = mappedPaths[0];
      NSString *fullDestinationPath = mappedPaths[1];
      NSError *error = nil;
      if (![NSFileManager.defaultManager moveItemAtPath:fullSourcePath toPath:fullDestinationPath error:&error]) {
        return [[[FBSimulatorError
          describeFormat:@"Could not move item at %@ to %@: %@", fullSourcePath, fullDestinationPath, error]
          causedBy:error]
          failFuture];
      }
      return FBFuture.empty;
    }];
}

- (FBFuture<NSNull *> *)remove:(NSString *)path
{
  return [[self
    mappedPath:path]
    onQueue:self.queue fmap:^ FBFuture<NSNull *> * (NSString *fullPath) {
      NSError *error;
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
    mappedPath:path]
    onQueue:self.queue fmap:^(NSString *fullPath) {
      NSError *error;
      NSArray<NSString *> *contents = [NSFileManager.defaultManager contentsOfDirectoryAtPath:fullPath error:&error];
      if (!contents) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:contents];
    }];
}

- (FBFuture<NSString *> *)mappedPath:(NSString *)path
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] must be implemented by subclasses", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFuture];
}

@end

@interface FBSimulatorBasePathFileContainer : FBSimulatorFileContainer

@property (nonatomic, copy, readonly) NSString *containerPath;

@end

@implementation FBSimulatorBasePathFileContainer

- (instancetype)initWithContainerPath:(NSString *)containerPath queue:(dispatch_queue_t)queue
{
  self = [super initWithQueue:queue];
  if (!self) {
    return nil;
  }

  _containerPath = containerPath;

  return self;
}

- (FBFuture<NSString *> *)mappedPath:(NSString *)path
{
  return [FBFuture futureWithResult:[self.containerPath stringByAppendingPathComponent:path]];
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
      return [[FBSimulatorBasePathFileContainer alloc] initWithContainerPath:containerPath queue:self.simulator.asyncQueue];
    }]
    onQueue:self.simulator.asyncQueue contextualTeardown:^(id _, FBFutureState __) {
      // Do nothing.
      return FBFuture.empty;
    }];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForRootFilesystem
{
  return [FBFutureContext futureContextWithResult:[[FBSimulatorBasePathFileContainer alloc] initWithContainerPath:self.simulator.dataDirectory queue:self.simulator.asyncQueue]];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForMediaDirectory
{
  return [FBFutureContext futureContextWithResult:[[FBSimulatorBasePathFileContainer alloc] initWithContainerPath:self.simulator.dataDirectory queue:self.simulator.asyncQueue]];
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
