/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorFileCommands.h"

#import "FBSimulator.h"
#import "FBSimulatorApplicationCommands.h"
#import "FBSimulatorError.h"

@interface FBSimulatorFileContainer : NSObject <FBFileContainer>

@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) NSFileManager *fileManager;

@end

@implementation FBSimulatorFileContainer

- (instancetype)initWithQueue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _queue = queue;
  _fileManager = NSFileManager.defaultManager;

  return self;
}

#pragma mark FBFileCommands

- (FBFuture<NSNull *> *)copyFromHost:(NSURL *)sourcePath toContainer:(NSString *)destinationPath
{
  return [[self
    mappedPath:destinationPath]
    onQueue:self.queue fmap:^ FBFuture<NSNull *> * (NSString *mappedPath) {
      NSError *error;
      NSString *destPath = [mappedPath stringByAppendingPathComponent:sourcePath.lastPathComponent];
      // Attempt to delete first to overwrite
      [self removeItemAtPath:destPath error:nil];
      if (![self copyItemAtPath:sourcePath.path toPath:destPath error:&error]) {
        return [[[FBSimulatorError
          describeFormat:@"Could not copy from %@ to %@: %@", sourcePath, destPath, error]
          causedBy:error]
          failFuture];
      }
      return FBFuture.empty;
    }];
}

- (FBFuture<NSString *> *)copyFromContainer:(NSString *)containerPath toHost:(NSString *)destinationPath
{
  return [[self
    mappedPath:containerPath]
    onQueue:self.queue fmap:^ FBFuture<NSString *> * (NSString *source) {
      BOOL srcIsDirecory = NO;
      if (![self.fileManager fileExistsAtPath:source isDirectory:&srcIsDirecory]) {
        return [[FBSimulatorError
          describeFormat:@"Source path does not exist: %@", source]
          failFuture];
      }
      NSString *dstPath = destinationPath;
      if (!srcIsDirecory) {
        NSError *createDirectoryError;
        if (![self createDirectoryAtPath:dstPath withIntermediateDirectories:YES attributes:nil error:&createDirectoryError]) {
          return [[[FBSimulatorError
            describeFormat:@"Could not create temporary directory: %@", createDirectoryError]
            causedBy:createDirectoryError]
            failFuture];
        }
        dstPath = [dstPath stringByAppendingPathComponent:[source lastPathComponent]];
      }
      // if it already exists at the destination path we should remove it before copying again
      if ([self.fileManager fileExistsAtPath:dstPath]) {
        NSError *removeError;
        if (![self removeItemAtPath:dstPath error:&removeError]) {
          return [[[FBSimulatorError
            describeFormat:@"Could not remove %@", dstPath]
            causedBy:removeError]
            failFuture];
        }
      }

      NSError *copyError;
      if (![self copyItemAtPath:source toPath:dstPath error:&copyError]) {
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
    onQueue:self.queue map:^(FBProcess *task) {
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
      if (![self createDirectoryAtPath:fullPath withIntermediateDirectories:YES attributes:nil error:&error]) {
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
      if (![self moveItemAtPath:fullSourcePath toPath:fullDestinationPath error:&error]) {
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
      if (![self removeItemAtPath:fullPath error:&error]) {
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
      NSArray<NSString *> *contents = [self contentsOfDirectoryAtPath:fullPath error:&error];
      if (!contents) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:contents];
    }];
}

#pragma mark Private

- (FBFuture<NSString *> *)mappedPath:(NSString *)path
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] must be implemented by subclasses", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFuture];
}

- (NSArray<NSString *> *)contentsOfDirectoryAtPath:(NSString *)fullPath error:(NSError **)error
{
  return [self.fileManager contentsOfDirectoryAtPath:fullPath error:error];
}

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error
{
  return [self.fileManager removeItemAtPath:path error:error];
}

- (BOOL)moveItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath error:(NSError **)error
{
  return [self.fileManager moveItemAtPath:srcPath toPath:dstPath error:error];
}

- (BOOL)copyItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath error:(NSError **)error
{
  return [self.fileManager copyItemAtPath:srcPath toPath:dstPath error:error];
}

- (BOOL)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)createIntermediates attributes:(NSDictionary<NSFileAttributeKey, id> *)attributes error:(NSError **)error
{
  return [self.fileManager createDirectoryAtPath:path withIntermediateDirectories:createIntermediates attributes:attributes error:error];
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

@interface FBSimulatorMappedFileContainer : FBSimulatorFileContainer;

@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *pathMapping;
@property (nonatomic, copy, readonly) NSSet<NSString *> *mappedPaths;

@end

@implementation FBSimulatorMappedFileContainer

- (instancetype)initWithPathMapping:(NSDictionary<NSString *, NSString *> *)pathMapping queue:(dispatch_queue_t)queue
{
  self = [super initWithQueue:queue];
  if (!self) {
    return nil;
  }

  _pathMapping = pathMapping;
  _mappedPaths = [NSSet setWithArray:pathMapping.allValues];

  return self;
}

- (FBFuture<NSString *> *)mappedPath:(NSString *)path
{
  NSArray<NSString *> *pathComponents = path.pathComponents;
  // If we're the root, there's nothing to map to.
  if ([self isRootPathOfContainer:pathComponents]) {
    return [FBFuture futureWithResult:path];
  }
  // Otherwise, take the first path component, which must be name of the container, so it must have a mapping.
  NSString *firstPath = pathComponents.firstObject;
  NSString *mappedPath = self.pathMapping[firstPath];
  if (!mappedPath) {
    return [[FBSimulatorError
      describeFormat:@"%@ is not a valid container id in %@", firstPath, [FBCollectionInformation oneLineDescriptionFromArray:self.pathMapping.allKeys]]
      failFuture];
  }
  // Re-assemble the mapped path, discarding the re-mapped first path component.
  BOOL isFirstPathComponent = YES;
  for (NSString *pathComponent in pathComponents) {
    if (isFirstPathComponent) {
      isFirstPathComponent = NO;
      continue;
    }
    mappedPath = [mappedPath stringByAppendingPathComponent:pathComponent];
  }
  return [FBFuture futureWithResult:mappedPath];
}

#pragma mark Private

- (NSArray<NSString *> *)contentsOfDirectoryAtPath:(NSString *)fullPath error:(NSError **)error
{
  NSArray<NSString *> *pathComponents = fullPath.pathComponents;
  // Request for the root container, list all mapped names.
  if ([self isRootPathOfContainer:pathComponents]) {
    return self.pathMapping.allKeys;
  }
  return [super contentsOfDirectoryAtPath:fullPath error:error];
}

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error
{
  NSArray<NSString *> *pathComponents = path.pathComponents;
  if ([self isRootPathOfContainer:pathComponents]) {
    return [[FBSimulatorError
      describeFormat:@"Cannot remove mapped container root at path %@", path]
      failBool:error];
  }
  if ([self isGroupContainerRoot:pathComponents]) {
    return [[FBSimulatorError
      describeFormat:@"Cannot remove mapped container at path %@", path]
      failBool:error];
  }
  return [super removeItemAtPath:path error:error];
}

- (BOOL)moveItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath error:(NSError **)error
{
  NSArray<NSString *> *srcPathComponents = srcPath.pathComponents;
  NSArray<NSString *> *dstPathComponents = dstPath.pathComponents;
  if ([self isRootPathOfContainer:srcPathComponents]) {
    return [[FBSimulatorError
      describeFormat:@"Cannot move mapped container root at path %@", srcPath]
      failBool:error];
  }
  if ([self isGroupContainerRoot:srcPathComponents]) {
    return [[FBSimulatorError
      describeFormat:@"Cannot move mapped container at path %@", srcPath]
      failBool:error];
  }
  if ([self isRootPathOfContainer:dstPathComponents]) {
    return [[FBSimulatorError
      describeFormat:@"Cannot move to mapped container root at path %@", dstPath]
      failBool:error];
  }
  if ([self isGroupContainerRoot:dstPathComponents]) {
    return [[FBSimulatorError
      describeFormat:@"Cannot move to mapped container at path %@", dstPath]
      failBool:error];
  }
  return [super moveItemAtPath:srcPath toPath:dstPath error:error];
}

- (BOOL)copyItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath error:(NSError **)error
{
  NSArray<NSString *> *srcPathComponents = srcPath.pathComponents;
  NSArray<NSString *> *dstPathComponents = dstPath.pathComponents;
  if ([self isRootPathOfContainer:srcPathComponents]) {
    return [[FBSimulatorError
      describeFormat:@"Cannot copy mapped container root at path %@", srcPath]
      failBool:error];
  }
  if ([self isRootPathOfContainer:dstPathComponents]) {
    return [[FBSimulatorError
      describeFormat:@"Cannot copy to mapped container root at path %@", dstPath]
      failBool:error];
  }
  if ([self isGroupContainerRoot:dstPathComponents]) {
    return [[FBSimulatorError
      describeFormat:@"Cannot copy to mapped container at path %@", dstPath]
      failBool:error];
  }
  return [super copyItemAtPath:srcPath toPath:dstPath error:error];
}

- (BOOL)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)createIntermediates attributes:(NSDictionary<NSFileAttributeKey, id> *)attributes error:(NSError **)error
{
  NSArray<NSString *> *pathComponents = path.pathComponents;
  if ([self isRootPathOfContainer:pathComponents]) {
    return [[FBSimulatorError
      describeFormat:@"Cannot create mapped container root at path %@", path]
      failBool:error];
  }
  if ([self isGroupContainerRoot:pathComponents]) {
    return [[FBSimulatorError
      describeFormat:@"Cannot create mapped container at path %@", path]
      failBool:error];
  }
  return [super createDirectoryAtPath:path withIntermediateDirectories:createIntermediates attributes:attributes error:error];
}

- (BOOL)isRootPathOfContainer:(NSArray<NSString *> *)pathComponents
{
  // If no path components this must be the root
  if (pathComponents.count == 0) {
    return YES;
  }
  // The root is also signified by a query for the root of the container.
  NSString *firstPath = pathComponents.firstObject;
  if (pathComponents.count == 1 && ([firstPath isEqualToString:@"."] || [firstPath isEqualToString:@"/"])) {
    return YES;
  }
  // Otherwise we can't be the root path.
  return NO;
}

- (BOOL)isGroupContainerRoot:(NSArray<NSString *> *)pathComponents
{
  // Re-assemble the path, confirming whether it matches with one of the mapped paths
  NSString *reassembled = [NSURL fileURLWithPathComponents:pathComponents].path;
  if ([self.mappedPaths containsObject:reassembled]) {
    return YES;
  }
  // If the canonical path does not match the known paths this can't be the group container root.
  return NO;
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

#pragma mark Public Methods

+ (id<FBFileContainer>)fileContainerForPathMapping:(NSDictionary<NSString *, NSString *> *)pathMapping queue:(dispatch_queue_t)queue
{
  return [[FBSimulatorMappedFileContainer alloc] initWithPathMapping:pathMapping queue:queue];
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

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForApplicationContainers
{
  return [[[FBSimulatorApplicationCommands
    applicationContainerToPathMappingForSimulator:self.simulator]
    onQueue:self.simulator.asyncQueue map:^(NSDictionary<NSString *, NSURL *> *pathMappingURLs) {
      NSMutableDictionary<NSString *, NSString *> *pathMapping = NSMutableDictionary.dictionary;
      for (NSString *identifier in pathMappingURLs.allKeys) {
        pathMapping[identifier] = pathMappingURLs[identifier].path;
      }
      return [FBSimulatorFileCommands fileContainerForPathMapping:pathMapping queue:self.simulator.asyncQueue];
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
      return [FBSimulatorFileCommands fileContainerForPathMapping:pathMapping queue:self.simulator.asyncQueue];
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
