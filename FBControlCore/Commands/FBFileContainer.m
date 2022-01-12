/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBFileContainer.h"

#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBProcessBuilder.h"
#import "FBProvisioningProfileCommands.h"

FBFileContainerKind const FBFileContainerKindApplication = @"application";
FBFileContainerKind const FBFileContainerKindAuxillary = @"auxillary";
FBFileContainerKind const FBFileContainerKindCrashes = @"crashes";
FBFileContainerKind const FBFileContainerKindDiskImages = @"disk_images";
FBFileContainerKind const FBFileContainerKindGroup = @"group";
FBFileContainerKind const FBFileContainerKindMDMProfiles = @"mdm_profiles";
FBFileContainerKind const FBFileContainerKindMedia = @"media";
FBFileContainerKind const FBFileContainerKindProvisioningProfiles = @"provisioning_profiles";
FBFileContainerKind const FBFileContainerKindRoot = @"root";
FBFileContainerKind const FBFileContainerKindSpringboardIcons = @"springboard_icons";
FBFileContainerKind const FBFileContainerKindSymbols = @"symbols";
FBFileContainerKind const FBFileContainerKindWallpaper = @"wallpaper";

@interface FBFileContainer_ProvisioningProfile : NSObject <FBFileContainer>

@property (nonatomic, strong, readonly) id<FBProvisioningProfileCommands> commands;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@implementation FBFileContainer_ProvisioningProfile

- (instancetype)initWithCommands:(id<FBProvisioningProfileCommands>)commands queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _commands = commands;
  _queue = queue;

  return self;
}

#pragma mark FBFileContainer Implementation

- (FBFuture<NSNull *> *)copyFromHost:(NSString *)path toContainer:(NSString *)destinationPath
{
  return [FBFuture
    onQueue:self.queue resolve:^ FBFuture<NSNull *> * {
      NSError *error = nil;
      NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&error];
      if (!data) {
        return [FBFuture futureWithError:error];
      }
      return [[self.commands installProvisioningProfile:data] mapReplace:NSNull.null];
    }];
}

- (FBFuture<NSString *> *)copyFromContainer:(NSString *)containerPath toHost:(NSString *)destinationPath
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] is not implemented", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<FBFuture<NSNull *> *> *)tail:(NSString *)containerPath toConsumer:(id<FBDataConsumer>)consumer
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] is not implemented", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)createDirectory:(NSString *)directoryPath
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] is not implemented", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)moveFrom:(NSString *)originPath to:(NSString *)destinationPath
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] is not implemented", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)remove:(NSString *)path
{
  return [[self.commands removeProvisioningProfile:path] mapReplace:NSNull.null];
}

- (FBFuture<NSArray<NSString *> *> *)contentsOfDirectory:(NSString *)path
{
  return [[self.commands
    allProvisioningProfiles]
    onQueue:self.queue map:^(NSArray<NSDictionary<NSString *,id> *> *profiles) {
      NSMutableArray<NSString *> *files = NSMutableArray.array;
      for (NSDictionary<NSString *,id> *profile in profiles) {
        [files addObject:profile[@"UUID"]];
      }
      return files;
    }];
}

@end

@interface FBFileContainerBase : NSObject <FBFileContainer>

@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) NSFileManager *fileManager;

@end

@implementation FBFileContainerBase

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

- (FBFuture<NSNull *> *)copyFromHost:(NSString *)sourcePath toContainer:(NSString *)destinationPath
{
  return [[self
    mappedPath:destinationPath]
    onQueue:self.queue fmap:^ FBFuture<NSNull *> * (NSString *mappedPath) {
      NSError *error;
      NSString *destPath = [mappedPath stringByAppendingPathComponent:sourcePath.lastPathComponent];
      // Attempt to delete first to overwrite
      [self removeItemAtPath:destPath error:nil];
      if (![self copyItemAtPath:sourcePath toPath:destPath error:&error]) {
        return [[[FBControlCoreError
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
        return [[FBControlCoreError
          describeFormat:@"Source path does not exist: %@", source]
          failFuture];
      }
      NSString *dstPath = destinationPath;
      if (!srcIsDirecory) {
        NSError *createDirectoryError;
        if (![self createDirectoryAtPath:dstPath withIntermediateDirectories:YES attributes:nil error:&createDirectoryError]) {
          return [[[FBControlCoreError
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
          return [[[FBControlCoreError
            describeFormat:@"Could not remove %@", dstPath]
            causedBy:removeError]
            failFuture];
        }
      }

      NSError *copyError;
      if (![self copyItemAtPath:source toPath:dstPath error:&copyError]) {
        return [[[FBControlCoreError
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
      return [[[[FBProcessBuilder
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
        return [[[FBControlCoreError
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
        return [[[FBControlCoreError
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
        return [[[FBControlCoreError
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

@interface FBBasePathFileContainer : FBFileContainerBase

@property (nonatomic, copy, readonly) NSString *containerPath;

@end

@implementation FBBasePathFileContainer

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

@interface FBMappedFileContainer : FBFileContainerBase

@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *pathMapping;
@property (nonatomic, copy, readonly) NSSet<NSString *> *mappedPaths;

@end

@implementation FBMappedFileContainer

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
    return [[FBControlCoreError
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
    return [[FBControlCoreError
      describeFormat:@"Cannot remove mapped container root at path %@", path]
      failBool:error];
  }
  if ([self isGroupContainerRoot:pathComponents]) {
    return [[FBControlCoreError
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
    return [[FBControlCoreError
      describeFormat:@"Cannot move mapped container root at path %@", srcPath]
      failBool:error];
  }
  if ([self isGroupContainerRoot:srcPathComponents]) {
    return [[FBControlCoreError
      describeFormat:@"Cannot move mapped container at path %@", srcPath]
      failBool:error];
  }
  if ([self isRootPathOfContainer:dstPathComponents]) {
    return [[FBControlCoreError
      describeFormat:@"Cannot move to mapped container root at path %@", dstPath]
      failBool:error];
  }
  if ([self isGroupContainerRoot:dstPathComponents]) {
    return [[FBControlCoreError
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
    return [[FBControlCoreError
      describeFormat:@"Cannot copy mapped container root at path %@", srcPath]
      failBool:error];
  }
  if ([self isRootPathOfContainer:dstPathComponents]) {
    return [[FBControlCoreError
      describeFormat:@"Cannot copy to mapped container root at path %@", dstPath]
      failBool:error];
  }
  if ([self isGroupContainerRoot:dstPathComponents]) {
    return [[FBControlCoreError
      describeFormat:@"Cannot copy to mapped container at path %@", dstPath]
      failBool:error];
  }
  return [super copyItemAtPath:srcPath toPath:dstPath error:error];
}

- (BOOL)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)createIntermediates attributes:(NSDictionary<NSFileAttributeKey, id> *)attributes error:(NSError **)error
{
  NSArray<NSString *> *pathComponents = path.pathComponents;
  if ([self isRootPathOfContainer:pathComponents]) {
    return [[FBControlCoreError
      describeFormat:@"Cannot create mapped container root at path %@", path]
      failBool:error];
  }
  if ([self isGroupContainerRoot:pathComponents]) {
    return [[FBControlCoreError
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

@implementation FBFileContainer

+ (id<FBFileContainer>)fileContainerForProvisioningProfileCommands:(id<FBProvisioningProfileCommands>)commands queue:(dispatch_queue_t)queue
{
  return [[FBFileContainer_ProvisioningProfile alloc] initWithCommands:commands queue:queue];
}

+ (id<FBFileContainer>)fileContainerForBasePath:(NSString *)basePath
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.file_container", DISPATCH_QUEUE_SERIAL);
  return [[FBBasePathFileContainer alloc] initWithContainerPath:basePath queue:queue];
}

+ (id<FBFileContainer>)fileContainerForPathMapping:(NSDictionary<NSString *, NSString *> *)pathMapping
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.file_container", DISPATCH_QUEUE_SERIAL);
  return [[FBMappedFileContainer alloc] initWithPathMapping:pathMapping queue:queue];
}

@end
