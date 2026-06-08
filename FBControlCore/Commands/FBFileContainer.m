/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBFileContainer.h"

#import "FBControlCore-Swift.h"
#import "FBControlCore-SwiftImport.h"

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
FBFileContainerKind const FBFileContainerKindXctest = @"xctest";
FBFileContainerKind const FBFileContainerKindDylib = @"dylib";
FBFileContainerKind const FBFileContainerKindDsym = @"dsym";
FBFileContainerKind const FBFileContainerKindFramework = @"framework";

@interface FBContainedFile_Host : NSObject <FBContainedFile>

@property (nonatomic, readonly, strong) NSFileManager *fileManager;
@property (nonatomic, readonly, copy) NSString *path;

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
             describe:[NSString stringWithFormat:@"Cannot move to %@, it is not on the host filesystem", destination]]
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

- (NSDictionary<NSString *, NSString *> *)pathMapping
{
  return nil;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"Host File %@", self.path];
}

@end

@interface FBContainedFile_Mapped_Host : NSObject <FBContainedFile>

@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *mappingPaths;
@property (nonatomic, readonly, strong) NSFileManager *fileManager;

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
           describe:[NSString stringWithFormat:@"%@ does not operate on root virtual containers", NSStringFromSelector(_cmd)]]
          failBool:error];
}

- (NSArray<NSString *> *)contentsOfDirectoryWithError:(NSError **)error
{
  return self.mappingPaths.allKeys;
}

- (BOOL)createDirectoryWithError:(NSError **)error
{
  return [[FBControlCoreError
           describe:[NSString stringWithFormat:@"%@ does not operate on root virtual containers", NSStringFromSelector(_cmd)]]
          failBool:error];
}

- (NSData *)contentsOfFileWithError:(NSError **)error
{
  return [[FBControlCoreError
           describe:[NSString stringWithFormat:@"%@ does not operate on root virtual containers", NSStringFromSelector(_cmd)]]
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
           describe:[NSString stringWithFormat:@"%@ does not operate on root virtual containers", NSStringFromSelector(_cmd)]]
          failBool:error];
}

- (BOOL)populateHostPathWithContents:(NSString *)path error:(NSError **)error
{
  return [[FBControlCoreError
           describe:[NSString stringWithFormat:@"%@ does not operate on root virtual containers", NSStringFromSelector(_cmd)]]
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
             describe:[NSString stringWithFormat:@"'%@' is not a valid root path out of %@", firstComponent, [FBCollectionInformation oneLineDescriptionFromArray:self.mappingPaths.allKeys]]]
            fail:error];
  }
  id<FBContainedFile> mapped = [[FBContainedFile_Host alloc] initWithFileManager:self.fileManager path:mappedPath];
  return [mapped fileByAppendingPathComponent:nextPath error:error];
}

- (NSString *)pathOnHostFileSystem
{
  return nil;
}

- (NSDictionary<NSString *, NSString *> *)pathMapping
{
  return self.mappingPaths;
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

@implementation FBFileContainer

+ (id)fileContainerForProvisioningProfileCommands:(id<FBProvisioningProfileCommands>)commands queue:(dispatch_queue_t)queue
{
  return [[FBFileContainer_ProvisioningProfile alloc] initWithCommands:commands];
}

+ (id<FBContainedFile>)containedFileForBasePath:(NSString *)basePath
{
  return [[FBContainedFile_Host alloc] initWithFileManager:NSFileManager.defaultManager path:basePath];
}

+ (id<FBContainedFile>)containedFileForPathMapping:(NSDictionary<NSString *, NSString *> *)pathMapping
{
  return [[FBContainedFile_Mapped_Host alloc] initWithMappingPaths:pathMapping fileManager:NSFileManager.defaultManager];
}

+ (id)fileContainerForBasePath:(NSString *)basePath
{
  id<FBContainedFile> rootFile = [self containedFileForBasePath:basePath];
  return [self fileContainerForContainedFile:rootFile];
}

+ (id)fileContainerForPathMapping:(NSDictionary<NSString *, NSString *> *)pathMapping
{
  id<FBContainedFile> rootFile = [self containedFileForPathMapping:pathMapping];
  return [self fileContainerForContainedFile:rootFile];
}

+ (id)fileContainerForContainedFile:(id<FBContainedFile>)containedFile
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.file_container", DISPATCH_QUEUE_SERIAL);
  return [[FBContainedFile_ContainedRoot alloc] initWithRootFile:containedFile queue:queue];
}

@end
