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

@interface FBContainedFile_Host : NSObject <FBContainedFile>

@property (nonatomic, strong, readonly) NSFileManager *fileManager;
@property (nonatomic, copy, readonly) NSString *path;

@end

@implementation FBContainedFile_Host

#pragma mark Initializers

- (instancetype)initWithFileManager:(NSFileManager *)fileManager path:(NSString *)path
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _fileManager = fileManager;
  _path = path;

  return self;
}

#pragma mark FBContainedFile

- (BOOL)removeItemWithError:(NSError **)error
{
  return [self.fileManager removeItemAtPath:self.path error:error];
}

- (NSArray<NSString *> *)contentsOfDirectoryWithError:(NSError **)error
{
  return [self.fileManager contentsOfDirectoryAtPath:self.path error:error];
}

- (NSData *)contentsOfFileWithError:(NSError **)error
{
  return [NSData dataWithContentsOfFile:self.path options:0 error:error];
}

- (BOOL)moveTo:(id<FBContainedFile>)destination error:(NSError **)error
{
  if (![destination isKindOfClass:FBContainedFile_Host.class]) {
    return [[FBControlCoreError
      describeFormat:@"Cannot move to %@, it is not on the host filesystem", destination]
      failBool:error];
  }
  FBContainedFile_Host *hostDestination = (FBContainedFile_Host *) destination;
  return [self.fileManager moveItemAtPath:self.path toPath:hostDestination.path error:error];
}

- (BOOL)createDirectoryWithError:(NSError **)error
{
  return [self.fileManager createDirectoryAtPath:self.path withIntermediateDirectories:YES attributes:nil error:error];
}

- (BOOL)fileExistsIsDirectory:(BOOL *)isDirectoryOut
{
  return [self.fileManager fileExistsAtPath:self.path isDirectory:isDirectoryOut];
}

- (BOOL)populateWithContentsOfHostPath:(NSString *)path error:(NSError **)error
{
  return [self.fileManager copyItemAtPath:path toPath:self.path error:error];
}

- (BOOL)populateHostPathWithContents:(NSString *)path error:(NSError **)error
{
  return [self.fileManager copyItemAtPath:self.path toPath:path error:error];
}

- (id<FBContainedFile>)fileByAppendingPathComponent:(NSString *)component error:(NSError **)error
{
  return [[FBContainedFile_Host alloc] initWithFileManager:self.fileManager path:[self.path stringByAppendingPathComponent:component]];
}

- (NSString *)pathOnHostFileSystem
{
  return self.path;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Host File %@", self.path];
}

@end

@interface FBContainedFile_Mapped_Host : NSObject <FBContainedFile>

@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *mappingPaths;
@property (nonatomic, strong, readonly) NSFileManager *fileManager;

@end

@implementation FBContainedFile_Mapped_Host

- (instancetype)initWithMappingPaths:(NSDictionary<NSString *, NSString *> *)mappingPaths fileManager:(NSFileManager *)fileManager;
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _mappingPaths = mappingPaths;
  _fileManager = fileManager;

  return self;
}

#pragma mark FBContainedFile

- (BOOL)removeItemWithError:(NSError **)error
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not operate on root virtual containers", NSStringFromSelector(_cmd)]
    failBool:error];
}

- (NSArray<NSString *> *)contentsOfDirectoryWithError:(NSError **)error
{
  return self.mappingPaths.allKeys;
}

- (BOOL)createDirectoryWithError:(NSError **)error
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not operate on root virtual containers", NSStringFromSelector(_cmd)]
    failBool:error];
}

- (NSData *)contentsOfFileWithError:(NSError **)error
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not operate on root virtual containers", NSStringFromSelector(_cmd)]
    fail:error];
}

- (BOOL)fileExistsIsDirectory:(BOOL *)isDirectoryOut
{
  return NO;
}

- (BOOL)moveTo:(id<FBContainedFile>)destination error:(NSError **)error
{
  return [[FBControlCoreError
    describe:@"Moving files does not work on root virtual containers"]
    failBool:error];
}

- (BOOL)populateWithContentsOfHostPath:(NSString *)path error:(NSError **)error
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not operate on root virtual containers", NSStringFromSelector(_cmd)]
    failBool:error];
}

- (BOOL)populateHostPathWithContents:(NSString *)path error:(NSError **)error
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not operate on root virtual containers", NSStringFromSelector(_cmd)]
    failBool:error];
}

- (id<FBContainedFile>)fileByAppendingPathComponent:(NSString *)component error:(NSError **)error
{
  // If the provided path represents the root (the mapping itself), then there's nothing to map to.
  NSArray<NSString *> *pathComponents = component.pathComponents;
  if ([FBContainedFile_Mapped_Host isRootPathOfContainer:pathComponents]) {
    return self;
  }
  NSString *firstComponent = pathComponents.firstObject;
  NSString *nextPath = [FBContainedFile_Mapped_Host popFirstPathComponent:pathComponents];
  NSString *mappedPath = self.mappingPaths[firstComponent];
  if (!mappedPath) {
    return [[FBControlCoreError
      describeFormat:@"'%@' is not a valid root path out of %@", firstComponent, [FBCollectionInformation oneLineDescriptionFromArray:self.mappingPaths.allKeys]]
      fail:error];
  }
  id<FBContainedFile> mapped = [[FBContainedFile_Host alloc] initWithFileManager:self.fileManager path:mappedPath];
  return [mapped fileByAppendingPathComponent:nextPath error:error];
}

- (NSString *)pathOnHostFileSystem
{
  return nil;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Root mapping: %@", [FBCollectionInformation oneLineDescriptionFromArray:self.mappingPaths.allKeys]];
}

#pragma mark Private

+ (BOOL)isRootPathOfContainer:(NSArray<NSString *> *)pathComponents
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
  // Otherwise we can't be the root path
  return NO;
}

+ (NSString *)popFirstPathComponent:(NSArray<NSString *> *)pathComponents
{
  // Re-assemble the mapped path, discarding the re-mapped first path component.
  BOOL isFirstPathComponent = YES;
  NSString *next = @"";
  for (NSString *pathComponent in pathComponents) {
    if (isFirstPathComponent) {
      isFirstPathComponent = NO;
      continue;
    }
    next = [next stringByAppendingPathComponent:pathComponent];
  }
  return next;
}

@end

@interface FBContainedFile_ContainedRoot : NSObject <FBFileContainer>

@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) id<FBContainedFile> rootFile;

@end

@implementation FBContainedFile_ContainedRoot

- (instancetype)initWithRootFile:(id<FBContainedFile>)rootFile queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _rootFile = rootFile;
  _queue = queue;

  return self;
}

#pragma mark FBFileCommands

- (FBFuture<NSNull *> *)copyFromHost:(NSString *)sourcePath toContainer:(NSString *)destinationPath
{
  return [[self
    mapToContainedFile:destinationPath]
    onQueue:self.queue fmap:^ FBFuture<NSNull *> * (id<FBContainedFile> destination) {
      // Attempt to delete first to overwrite
      NSError *error;
      destination = [destination fileByAppendingPathComponent:sourcePath.lastPathComponent error:&error];
      if (!destination) {
        return [FBFuture futureWithError:error];
      }
      [destination removeItemWithError:nil];
      if (![destination populateWithContentsOfHostPath:sourcePath error:&error]) {
        return [[[FBControlCoreError
          describeFormat:@"Could not copy from %@ to %@: %@", sourcePath, destinationPath, error]
          causedBy:error]
          failFuture];
      }
      return FBFuture.empty;
    }];
}

- (FBFuture<NSString *> *)copyFromContainer:(NSString *)sourcePath toHost:(NSString *)destinationPath
{
  return [[self
    mapToContainedFile:sourcePath]
    onQueue:self.queue fmap:^ FBFuture<NSString *> * (id<FBContainedFile> source) {
      BOOL sourceIsDirectory = NO;
      if (![source fileExistsIsDirectory:&sourceIsDirectory]) {
        return [[FBControlCoreError
          describeFormat:@"Source path does not exist: %@", source]
          failFuture];
      }
      NSString *dstPath = destinationPath;
      if (!sourceIsDirectory) {
        NSError *createDirectoryError;
        if (![NSFileManager.defaultManager createDirectoryAtPath:dstPath withIntermediateDirectories:YES attributes:@{} error:&createDirectoryError]) {
          return [[[FBControlCoreError
            describeFormat:@"Could not create temporary directory: %@", createDirectoryError]
            causedBy:createDirectoryError]
            failFuture];
        }
        dstPath = [dstPath stringByAppendingPathComponent:[sourcePath lastPathComponent]];
      }
      // if it already exists at the destination path we should remove it before copying again
      BOOL destinationIsDirectory = NO;
      if ([NSFileManager.defaultManager fileExistsAtPath:dstPath isDirectory:&destinationIsDirectory]) {
        NSError *removeError;
        if (![NSFileManager.defaultManager removeItemAtPath:dstPath error:&removeError]) {
          return [[[FBControlCoreError
            describeFormat:@"Could not remove %@", dstPath]
            causedBy:removeError]
            failFuture];
        }
      }

      NSError *copyError;
      if (![source populateHostPathWithContents:dstPath error:&copyError]) {
        return [[[FBControlCoreError
          describeFormat:@"Could not copy from %@ to %@: %@", source, dstPath, copyError]
          causedBy:copyError]
          failFuture];
      }
      return [FBFuture futureWithResult:destinationPath];
    }];
}

- (FBFuture<FBFuture<NSNull *> *> *)tail:(NSString *)path toConsumer:(id<FBDataConsumer>)consumer
{
  return [[[self
    mapToContainedFile:path]
    onQueue:self.queue fmap:^ FBFuture<FBProcess<NSNull *, id<FBDataConsumer>, NSData *> *> * (id<FBContainedFile> fileToTail) {
      NSString *pathOnHostFileSystem = fileToTail.pathOnHostFileSystem;
      if (!pathOnHostFileSystem) {
        return [[FBControlCoreError
          describeFormat:@"Cannot tail %@, it is not on the local filesystem", fileToTail]
          failFuture];
      }
      return [[[[FBProcessBuilder
        withLaunchPath:@"/usr/bin/tail"]
        withArguments:@[@"-c+1", @"-f", pathOnHostFileSystem]]
        withStdOutConsumer:consumer]
        start];
    }]
    onQueue:self.queue map:^(FBProcess *process) {
      return [process.statLoc
        onQueue:self.queue respondToCancellation:^{
          return [process sendSignal:SIGTERM backingOffToKillWithTimeout:1 logger:nil];
        }];
    }];
}

- (FBFuture<NSNull *> *)createDirectory:(NSString *)directoryPath
{
  return [[self
    mapToContainedFile:directoryPath]
    onQueue:self.queue fmap:^ FBFuture<NSNull *> * (id<FBContainedFile> directory) {
      NSError *error;
      if (![directory createDirectoryWithError:&error]) {
        return [[[FBControlCoreError
          describeFormat:@"Could not create directory %@: %@", directory, error]
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
      [self mapToContainedFile:sourcePath],
      [self mapToContainedFile:destinationPath],
    ]]
    onQueue:self.queue fmap:^ FBFuture<NSNull *> * (NSArray<id<FBContainedFile>> *providedFiles) {
      // If the source and destination are on the same filesystem, they can be moved directly.
      id<FBContainedFile> source = providedFiles[0];
      id<FBContainedFile> destination = providedFiles[1];
      NSError *error = nil;
      if (![source moveTo:destination error:&error]) {
        return [[[FBControlCoreError
          describeFormat:@"Could not move item at %@ to %@: %@", source, destination, error]
          causedBy:error]
          failFuture];
      }
      return FBFuture.empty;
    }];
}

- (FBFuture<NSNull *> *)remove:(NSString *)path
{
  return [[self
    mapToContainedFile:path]
    onQueue:self.queue fmap:^ FBFuture<NSNull *> * (id<FBContainedFile> file) {
      NSError *error;
      if (![file removeItemWithError:&error]) {
        return [[[FBControlCoreError
          describeFormat:@"Could not remove item at path %@: %@", file, error]
          causedBy:error]
          failFuture];
      }
      return FBFuture.empty;
    }];
}

- (FBFuture<NSArray<NSString *> *> *)contentsOfDirectory:(NSString *)path
{
  return [[self
    mapToContainedFile:path]
    onQueue:self.queue fmap:^(id<FBContainedFile> directory) {
      NSError *error;
      NSArray<NSString *> *contents = [directory contentsOfDirectoryWithError:&error];
      if (!contents) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:contents];
    }];
}

#pragma mark Private

- (FBFuture<id<FBContainedFile>> *)mapToContainedFile:(NSString *)path
{
  NSError *error = nil;
  id<FBContainedFile> file = [self.rootFile fileByAppendingPathComponent:path error:&error];
  if (!file) {
    return [FBFuture futureWithError:error];
  }
  return [FBFuture futureWithResult:file];
}

@end

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

@implementation FBFileContainer

+ (id<FBFileContainer>)fileContainerForProvisioningProfileCommands:(id<FBProvisioningProfileCommands>)commands queue:(dispatch_queue_t)queue
{
  return [[FBFileContainer_ProvisioningProfile alloc] initWithCommands:commands queue:queue];
}

+ (id<FBFileContainer>)fileContainerForBasePath:(NSString *)basePath
{
  id<FBContainedFile> rootFile = [[FBContainedFile_Host alloc] initWithFileManager:NSFileManager.defaultManager path:basePath];
  return [self fileContainerForRootFile:rootFile];
}

+ (id<FBFileContainer>)fileContainerForPathMapping:(NSDictionary<NSString *, NSString *> *)pathMapping
{
  id<FBContainedFile> rootFile = [[FBContainedFile_Mapped_Host alloc] initWithMappingPaths:pathMapping fileManager:NSFileManager.defaultManager];
  return [self fileContainerForRootFile:rootFile];
}

#pragma mark Private

+ (id<FBFileContainer>)fileContainerForRootFile:(id<FBContainedFile>)root
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.file_container", DISPATCH_QUEUE_SERIAL);
  return [[FBContainedFile_ContainedRoot alloc] initWithRootFile:root queue:queue];
}

@end
