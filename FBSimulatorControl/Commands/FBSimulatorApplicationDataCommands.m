/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorApplicationDataCommands.h"

#import "FBSimulator.h"
#import "FBSimulatorError.h"

@interface FBSimulatorFileCommands : NSObject <FBiOSTargetFileCommands>

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@end

@interface FBSimulatorFileCommands_AppContainer : FBSimulatorFileCommands

@property (nonatomic, copy, readonly) NSString *bundleID;

@end

@implementation FBSimulatorFileCommands

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;

  return self;
}

#pragma mark FBApplicationDataCommands

- (FBFuture<NSNull *> *)copyPathsOnHost:(NSArray<NSURL *> *)paths toDestination:(NSString *)destinationPath
{
  return [[self
    dataContainer]
    onQueue:self.simulator.asyncQueue fmap:^ FBFuture<NSNull *> * (NSString *dataContainer) {
      NSError *error;
      NSURL *basePathURL =  [NSURL fileURLWithPathComponents:@[dataContainer, destinationPath]];
      NSFileManager *fileManager = NSFileManager.defaultManager;
      for (NSURL *url in paths) {
        NSURL *destURL = [basePathURL URLByAppendingPathComponent:url.lastPathComponent];
        if (![fileManager copyItemAtURL:url toURL:destURL error:&error]) {
          return [[[FBSimulatorError
            describeFormat:@"Could not copy from %@ to %@: %@", url, destURL, error]
            causedBy:error]
            failFuture];
        }
      }
      return FBFuture.empty;
    }];
}

- (FBFuture<NSString *> *)copyItemInContainer:(NSString *)containerPath toDestinationOnHost:(NSString *)destinationPath
{
  __block NSString *dstPath = destinationPath;
  return [[self
    dataContainer]
    onQueue:self.simulator.asyncQueue fmap:^ FBFuture<NSString *> * (NSString *dataContainer) {
      NSString *source = [dataContainer stringByAppendingPathComponent:containerPath];
      BOOL srcIsDirecory = NO;
      if ([NSFileManager.defaultManager fileExistsAtPath:source isDirectory:&srcIsDirecory] && !srcIsDirecory) {
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
    onQueue:self.simulator.asyncQueue fmap:^ FBFuture<NSNull *> * (NSString *dataContainer) {
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

- (FBFuture<NSNull *> *)movePaths:(NSArray<NSString *> *)originPaths toDestinationPath:(NSString *)destinationPath
{
  return [[self
    dataContainer]
    onQueue:self.simulator.asyncQueue fmap:^ FBFuture<NSNull *> * (NSString *dataContainer) {
      NSError *error;
      NSString *fullDestinationPath = [dataContainer stringByAppendingPathComponent:destinationPath];
      for (NSString *originPath in originPaths) {
        NSString *fullOriginPath = [dataContainer stringByAppendingPathComponent:originPath];
        if (![NSFileManager.defaultManager moveItemAtPath:fullOriginPath toPath:fullDestinationPath error:&error]) {
          return [[[FBSimulatorError
            describeFormat:@"Could not move item at %@ to %@: %@", fullOriginPath, fullDestinationPath, error]
            causedBy:error]
            failFuture];
        }
      }
      return FBFuture.empty;
    }];
}

- (FBFuture<NSNull *> *)removePaths:(NSArray<NSString *> *)paths
{
  return [[self
    dataContainer]
    onQueue:self.simulator.asyncQueue fmap:^ FBFuture<NSNull *> * (NSString *dataContainer) {
      NSError *error;
      for (NSString *path in paths) {
        NSString *fullPath = [dataContainer stringByAppendingPathComponent:path];
        if (![NSFileManager.defaultManager removeItemAtPath:fullPath error:&error]) {
          return [[[FBSimulatorError
            describeFormat:@"Could not remove item at path %@: %@", fullPath, error]
            causedBy:error]
            failFuture];
        }
      }
      return FBFuture.empty;
    }];
}

- (FBFuture<NSArray<NSString *> *> *)contentsOfDirectory:(NSString *)path
{
  return [[self
    dataContainer]
    onQueue:self.simulator.asyncQueue fmap:^(NSString *dataContainer) {
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
  return [FBFuture futureWithResult:self.simulator.dataDirectory];
}

@end

@implementation FBSimulatorFileCommands_AppContainer

- (instancetype)initWithSimulator:(FBSimulator *)simulator bundleID:(NSString *)bundleID
{
  self = [super initWithSimulator:simulator];
  if (!self) {
    return nil;
  }

  _bundleID = bundleID;

  return self;
}

#pragma mark Private

- (FBFuture<NSString *> *)dataContainer
{
  return [[self.simulator
    installedApplicationWithBundleID:self.bundleID]
    onQueue:self.simulator.asyncQueue chain:^FBFuture<NSString *> *(FBFuture<FBInstalledApplication *> *future) {
      NSString *container = future.result.dataContainer;
      if (container) {
        return [FBFuture futureWithResult:container];
      }
      return [self fallbackDataContainer];
    }];
}

- (FBFuture<NSString *> *)fallbackDataContainer
{
  return [[self.simulator
    runningApplicationWithBundleID:self.bundleID]
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

@interface FBSimulatorApplicationDataCommands ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;

@end

@implementation FBSimulatorApplicationDataCommands

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

#pragma mark FBApplicationDataCommands Implementation

- (id<FBiOSTargetFileCommands>)fileCommandsForContainerApplication:(NSString *)bundleID
{
  return [[FBSimulatorFileCommands_AppContainer alloc] initWithSimulator:self.simulator bundleID:bundleID];
}

- (id<FBiOSTargetFileCommands>)fileCommandsForRootFilesystem
{
  return [[FBSimulatorFileCommands alloc] initWithSimulator:self.simulator];
}

@end
