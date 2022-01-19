/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceFileCommands.h"

#import "FBAFCConnection.h"
#import "FBDevice+Private.h"
#import "FBDevice.h"
#import "FBDeviceControlError.h"
#import "FBDeviceDebugSymbolsCommands.h"
#import "FBDeviceProvisioningProfileCommands.h"
#import "FBManagedConfigClient.h"
#import "FBSpringboardServicesClient.h"

@interface FBDeviceFileContainer ()

@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) FBAFCConnection *connection;

@end

@implementation FBDeviceFileContainer

- (instancetype)initWithAFCConnection:(FBAFCConnection *)connection queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _connection = connection;
  _queue = queue;

  return self;
}

- (FBFuture<NSNull *> *)copyFromHost:(NSString *)sourcePath toContainer:(NSString *)destinationPath
{
  return [self handleAFCOperation:^ NSNull * (FBAFCConnection *afc, NSError **error) {
    BOOL success = [afc copyFromHost:sourcePath toContainerPath:destinationPath error:error];
    if (!success) {
      return nil;
    }
    return NSNull.null;
  }];
}

- (FBFuture<NSString *> *)copyFromContainer:(NSString *)sourcePath toHost:(NSString *)destinationPath
{
  NSString *destination = destinationPath;
  if ([FBDeviceFileContainer isDirectory:destinationPath]){
    destination = [destinationPath stringByAppendingPathComponent:sourcePath.lastPathComponent];
  }
  return [[self
    readFileFromPathInContainer:sourcePath]
    onQueue:self.queue fmap:^FBFuture<NSString *> *(NSData *fileData) {
     NSError *error;
     if (![fileData writeToFile:destination options:0 error:&error]) {
       return [[[FBDeviceControlError
        describeFormat:@"Failed to write data to file at path %@", destination]
        causedBy:error]
        failFuture];
     }
     return [FBFuture futureWithResult:destination];
   }];
}

- (FBFuture<FBFuture<NSNull *> *> *)tail:(NSString *)path toConsumer:(id<FBDataConsumer>)consumer
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] is not implemented", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)createDirectory:(NSString *)directoryPath
{
  return [self handleAFCOperation:^ NSNull * (FBAFCConnection *afc, NSError **error) {
    BOOL success = [afc createDirectory:directoryPath error:error];
    if (!success) {
      return nil;
    }
    return NSNull.null;
  }];
}

- (FBFuture<NSNull *> *)moveFrom:(NSString *)sourcePath to:(NSString *)destinationPath
{
  return [self handleAFCOperation:^ NSNull * (FBAFCConnection *afc, NSError **error) {
    BOOL success = [afc renamePath:sourcePath destination:destinationPath error:error];
    if (!success) {
      return nil;
    }
    return NSNull.null;
  }];
}

- (FBFuture<NSNull *> *)remove:(NSString *)path
{
  return [self handleAFCOperation:^ NSNull * (FBAFCConnection *afc, NSError **error) {
    BOOL success = [afc removePath:path recursively:YES error:error];
    if (!success) {
      return nil;
    }
    return NSNull.null;
  }];
}

- (FBFuture<NSArray<NSString *> *> *)contentsOfDirectory:(NSString *)path
{
  return [self handleAFCOperation:^ NSArray<NSString *> * (FBAFCConnection *afc, NSError **error) {
    return [afc contentsOfDirectory:path error:error];
  }];
}

#pragma mark Private

- (FBFuture<NSData *> *)readFileFromPathInContainer:(NSString *)path
{
  return [self handleAFCOperation:^ NSData * (FBAFCConnection *afc, NSError **error) {
    return [afc contentsOfPath:path error:error];
  }];
}

- (FBFuture *)handleAFCOperation:(id(^)(FBAFCConnection *, NSError **))operationBlock
{
  return [FBFuture
  onQueue:self.queue resolveValue:^(NSError **error) {
      return operationBlock(self.connection, error);
  }];
}

+ (BOOL)isDirectory:(NSString *)path
{
  BOOL isDir = NO;
  return ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDir] && isDir);
}

@end

@interface FBDeviceFileContainer_Wallpaper : NSObject <FBFileContainer>

@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) FBSpringboardServicesClient *springboard;
@property (nonatomic, strong, readonly) FBManagedConfigClient *managedConfig;

@end

@implementation FBDeviceFileContainer_Wallpaper

- (instancetype)initWithSpringboard:(FBSpringboardServicesClient *)springboard managedConfig:(FBManagedConfigClient *)managedConfig queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _springboard = springboard;
  _managedConfig = managedConfig;
  _queue = queue;

  return self;
}

#pragma mark FBFileContainer Implementation

- (FBFuture<NSArray<NSString *> *> *)contentsOfDirectory:(NSString *)path
{
  return [FBFuture futureWithResult:@[FBWallpaperNameHomescreen, FBWallpaperNameLockscreen]];
}

- (FBFuture<NSString *> *)copyFromContainer:(NSString *)sourcePath toHost:(NSString *)destinationPath
{
  return [[self.springboard
    wallpaperImageDataForKind:sourcePath.lastPathComponent]
    onQueue:self.queue fmap:^ FBFuture<NSString *> * (NSData *data) {
      NSError *error = nil;
      if (![data writeToFile:destinationPath options:NSDataWritingAtomic error:&error]) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:destinationPath];
    }];
}

- (FBFuture<NSNull *> *)copyFromHost:(NSString *)sourcePath toContainer:(NSString *)destinationPath
{
  return [FBFuture
    onQueue:self.queue resolve:^ FBFuture<NSNull *> * {
      NSError *error = nil;
      NSData *data = [NSData dataWithContentsOfFile:sourcePath options:0 error:&error];
      if (!data) {
        return [FBFuture futureWithError:error];
      }
      return [self.managedConfig changeWallpaperWithName:destinationPath.lastPathComponent data:data];
    }];
}

- (FBFuture<FBFuture<NSNull *> *> *)tail:(NSString *)path toConsumer:(id<FBDataConsumer>)consumer
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] is not implemented", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)createDirectory:(NSString *)directoryPath
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not make sense for Wallpaper File Containers", NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)moveFrom:(NSString *)sourcePath to:(NSString *)destinationPath
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not make sense for Wallpaper File Containers", NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)remove:(NSString *)path
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not make sense for Wallpaper File Containers", NSStringFromSelector(_cmd)]
    failFuture];
}

@end

@interface FBDeviceFileContainer_MDMProfiles : NSObject <FBFileContainer>

@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) FBManagedConfigClient *managedConfig;

@end

@implementation FBDeviceFileContainer_MDMProfiles

- (instancetype)initWithManagedConfig:(FBManagedConfigClient *)managedConfig queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _managedConfig = managedConfig;
  _queue = queue;

  return self;
}

#pragma mark FBFileContainer Implementation

- (FBFuture<NSArray<NSString *> *> *)contentsOfDirectory:(NSString *)path
{
  return [self.managedConfig getProfileList];
}

- (FBFuture<NSString *> *)copyFromContainer:(NSString *)sourcePath toHost:(NSString *)destinationPath
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not make sense for MDM Profile File Containers", NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)copyFromHost:(NSString *)sourcePath toContainer:(NSString *)destinationPath
{
  return [FBFuture
    onQueue:self.queue resolve:^ FBFuture<NSNull *> * {
      NSError *error = nil;
      NSData *data = [NSData dataWithContentsOfFile:sourcePath options:0 error:&error];
      if (!data) {
        return [FBFuture futureWithError:error];
      }
      return [self.managedConfig installProfile:data];
    }];
}

- (FBFuture<FBFuture<NSNull *> *> *)tail:(NSString *)path toConsumer:(id<FBDataConsumer>)consumer
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] is not implemented", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)createDirectory:(NSString *)directoryPath
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not make sense for MDM Profile File Containers", NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)moveFrom:(NSString *)sourcePath to:(NSString *)destinationPath
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not make sense for MDM Profile File Containers", NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)remove:(NSString *)path
{
  return [self.managedConfig removeProfile:path];
}

@end

static NSString *const MountRootPath = @"mounted";

@interface FBDeviceFileCommands_DiskImages : NSObject <FBFileContainer>

@property (nonatomic, strong, readonly) id<FBDeveloperDiskImageCommands> commands;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@implementation FBDeviceFileCommands_DiskImages

- (instancetype)initWithCommands:(id<FBDeveloperDiskImageCommands>)commands queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _commands = commands;
  _queue = queue;

  return self;
}

- (FBFuture<NSNull *> *)copyFromHost:(NSString *)sourcePath toContainer:(NSString *)destinationPath
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not make sense for Disk Images", NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSString *> *)copyFromContainer:(NSString *)sourcePath toHost:(NSString *)destinationPath
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not make sense for Disk Images", NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<FBFuture<NSNull *> *> *)tail:(NSString *)path toConsumer:(id<FBDataConsumer>)consumer
{
  return [[FBControlCoreError
    describeFormat:@"-[%@ %@] is not implemented", NSStringFromClass(self.class), NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)createDirectory:(NSString *)directoryPath
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not make sense for Disk Images", NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)moveFrom:(NSString *)sourcePath to:(NSString *)destinationPath
{
  if (![destinationPath hasPrefix:MountRootPath]) {
    return [[FBDeviceControlError
      describeFormat:@"%@ only moving into mounts is supported.", destinationPath]
      failFuture];
  }
  NSDictionary<NSString *, FBDeveloperDiskImage *> *mountableImagesByPath = self.mountableDiskImagesByPath;
  FBDeveloperDiskImage *image = mountableImagesByPath[sourcePath];
  if (!image) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not one of %@", sourcePath, [FBCollectionInformation oneLineDescriptionFromArray:mountableImagesByPath.allKeys]]
      failFuture];
  }
  return [[self.commands
    mountDiskImage:image]
    mapReplace:NSNull.null];
}

- (FBFuture<NSNull *> *)remove:(NSString *)path
{
  if (![path hasPrefix:MountRootPath]) {
    return [[FBDeviceControlError
      describeFormat:@"%@ cannot be removed, only mounts can be removed", path]
      failFuture];
  }
  return [[self
    mountedDiskImages]
    onQueue:self.queue fmap:^ FBFuture<NSNull *> * (NSDictionary<NSString *, FBDeveloperDiskImage *> *mountedImages) {
      FBDeveloperDiskImage *image = mountedImages[path];
      if (!image) {
        return [[FBDeviceControlError
          describeFormat:@"%@ is not one of the available mounts %@", path, [FBCollectionInformation oneLineDescriptionFromArray:mountedImages.allKeys]]
          failFuture];
      }
      return [self.commands unmountDiskImage:image];
    }];
}

- (FBFuture<NSArray<NSString *> *> *)contentsOfDirectory:(NSString *)path
{
  return [[self
    allDiskImagePaths]
    onQueue:self.queue fmap:^(NSArray<NSString *> *diskImagePaths) {
      NSError *error = nil;
      NSArray<NSString *> *traversedPaths = [FBDeviceFileCommands_DiskImages traverseAndDescendPaths:diskImagePaths path:path error:&error];
      if (!traversedPaths) {
        return [FBFuture futureWithError:error];
      }
      return  [FBFuture futureWithResult:traversedPaths];
    }];
}

#pragma mark Private

- (NSDictionary<NSString *, FBDeveloperDiskImage *> *)mountableDiskImagesByPath
{
  NSArray<FBDeveloperDiskImage *> *images = self.commands.mountableDiskImages;
  NSMutableDictionary<NSString *, FBDeveloperDiskImage *> *mapping = NSMutableDictionary.dictionary;
  for (FBDeveloperDiskImage *image in images) {
    NSString *mapped = [FBDeviceFileCommands_DiskImages filePathForImage:image];
    mapping[mapped] = image;
  }
  return mapping;
}

- (FBFuture<NSDictionary<NSString *, FBDeveloperDiskImage *> *> *)mountedDiskImages
{
  return [[self.commands
    mountedDiskImages]
    onQueue:self.queue map:^(NSArray<FBDeveloperDiskImage *> *mountedImages) {
      NSMutableDictionary<NSString *, FBDeveloperDiskImage *> *imagesByPath = NSMutableDictionary.dictionary;
      for (FBDeveloperDiskImage *image in mountedImages) {
        NSString *mountedFilePath = [MountRootPath stringByAppendingPathComponent:[FBDeviceFileCommands_DiskImages filePathForImage:image]];
        imagesByPath[mountedFilePath] = image;
      }
      return [imagesByPath copy];
    }];
}

- (FBFuture<NSArray<NSString *> *> *)allDiskImagePaths
{
  return [[self
    mountedDiskImages]
    onQueue:self.queue map:^(NSDictionary<NSString *, FBDeveloperDiskImage *> *mountedDiskImages) {
      // Construct the full list of all paths, including the mounted & available images.
      NSMutableArray<NSString *> *paths = NSMutableArray.array;
      [paths addObjectsFromArray:[self.mountableDiskImagesByPath keysSortedByValueUsingSelector:@selector(compare:)]];
      [paths addObject:MountRootPath];
      [paths addObjectsFromArray:mountedDiskImages.allKeys];
      return [paths copy];
    }];
}

+ (NSArray<NSString *> *)traverseAndDescendPaths:(NSArray<NSString *> *)paths path:(NSString *)path error:(NSError **)error
{
  NSArray<NSString *> *pathComponents = [path pathComponents];
  NSString *firstPath = [pathComponents firstObject];
  if (pathComponents.count == 1 && ([firstPath isEqualToString:@"."] || [firstPath isEqualToString:@"/"])) {
    return paths;
  }
  NSMutableArray<NSString *> *traversedPaths = NSMutableArray.array;
  for (NSString *candidatePath in paths) {
    if (![candidatePath hasPrefix:path]) {
      continue;
    }
    NSString *relativePath = [candidatePath substringFromIndex:path.length];
    if ([relativePath hasPrefix:@"/"]) {
      relativePath = [relativePath substringFromIndex:1];
    }
    [traversedPaths addObject:relativePath];
  }
  return [traversedPaths copy];
}

+ (NSString *)filePathForImage:(FBDeveloperDiskImage *)image
{
  return [NSString stringWithFormat:@"%ld.%ld/%@", image.version.majorVersion, image.version.minorVersion, image.diskImagePath.lastPathComponent];
}

@end

@interface FBDeviceFileCommands_Symbols : NSObject <FBFileContainer>

@property (nonatomic, strong, readonly) id<FBDeviceDebugSymbolsCommands> commands;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@implementation FBDeviceFileCommands_Symbols

static NSString *const ExtractedSymbolsDirectory = @"Symbols";

- (instancetype)initWithCommands:(id<FBDeviceDebugSymbolsCommands>)commands queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _commands = commands;
  _queue = queue;

  return self;
}

- (FBFuture<NSNull *> *)copyFromHost:(NSURL *)sourcePath toContainer:(NSString *)destinationPath
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not make sense for Symbols", NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSString *> *)copyFromContainer:(NSString *)sourcePath toHost:(NSString *)destinationPath
{
  if ([sourcePath isEqualToString:ExtractedSymbolsDirectory]) {
    return [self.commands pullAndExtractSymbolsToDestinationDirectory:destinationPath];
  }
  return [self.commands pullSymbolFile:sourcePath toDestinationPath:destinationPath];
}

- (FBFuture<FBFuture<NSNull *> *> *)tail:(NSString *)path toConsumer:(id<FBDataConsumer>)consumer
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not make sense for Symbols", NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)createDirectory:(NSString *)directoryPath
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not make sense for Symbols", NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)moveFrom:(NSString *)sourcePath to:(NSString *)destinationPath
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not make sense for Symbols", NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)remove:(NSString *)path
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not make sense for Symbols", NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSArray<NSString *> *> *)contentsOfDirectory:(NSString *)path
{
  return [[self.commands
    listSymbols]
    onQueue:self.queue map:^(NSArray<NSString *> *listedSymbols) {
      return [listedSymbols arrayByAddingObject:ExtractedSymbolsDirectory];
    }];
}

@end


@interface FBDeviceFileCommands ()

@property (nonatomic, strong, readonly) FBDevice *device;
@property (nonatomic, assign, readonly) AFCCalls afcCalls;

@end

@implementation FBDeviceFileCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBDevice *)target afcCalls:(AFCCalls)afcCalls
{
  return [[self alloc] initWithDevice:target afcCalls:afcCalls];
}

+ (instancetype)commandsWithTarget:(FBDevice *)target
{
  return [self commandsWithTarget:target afcCalls:FBAFCConnection.defaultCalls];
}

- (instancetype)initWithDevice:(FBDevice *)device afcCalls:(AFCCalls)afcCalls
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  _afcCalls = afcCalls;

  return self;
}

#pragma mark FBFileCommands

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForContainerApplication:(NSString *)bundleID
{
  return [[self.device
    houseArrestAFCConnectionForBundleID:bundleID afcCalls:self.afcCalls]
    onQueue:self.device.asyncQueue pend:^ FBFuture<id<FBFileContainer>> * (FBAFCConnection *connection) {
      return [FBFuture futureWithResult:[[FBDeviceFileContainer alloc] initWithAFCConnection:connection queue:self.device.asyncQueue]];
    }];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForAuxillary
{
  return [FBFutureContext futureContextWithResult:[FBFileContainer fileContainerForBasePath:self.device.auxillaryDirectory]];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForApplicationContainers
{
  return [[FBControlCoreError
    describeFormat:@"%@ not supported on devices, requires a rooted device", NSStringFromSelector(_cmd)]
    failFutureContext];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForGroupContainers
{
  return [[FBControlCoreError
    describeFormat:@"%@ not supported on devices, requires a rooted device", NSStringFromSelector(_cmd)]
    failFutureContext];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForRootFilesystem
{
  return [[FBControlCoreError
    describeFormat:@"%@ not supported on devices, requires a rooted device", NSStringFromSelector(_cmd)]
    failFutureContext];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForMediaDirectory
{
  return [[self.device
    startAFCService:@"com.apple.afc"]
    onQueue:self.device.asyncQueue pend:^ FBFuture<id<FBFileContainer>> * (FBAFCConnection *connection) {
      return [FBFuture futureWithResult:[[FBDeviceFileContainer alloc] initWithAFCConnection:connection queue:self.device.asyncQueue]];
    }];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForProvisioningProfiles
{
  return [FBFutureContext futureContextWithResult:[FBFileContainer fileContainerForProvisioningProfileCommands:[FBDeviceProvisioningProfileCommands commandsWithTarget:self.device] queue:self.device.workQueue]];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForMDMProfiles
{
  return [[self.device
    startService:FBManagedConfigService]
    onQueue:self.device.asyncQueue pend:^ FBFuture<id<FBFileContainer>> * (FBAMDServiceConnection *connection) {
      FBManagedConfigClient *managedConfig = [FBManagedConfigClient managedConfigClientWithConnection:connection logger:self.device.logger];
      return [FBFuture futureWithResult:[[FBDeviceFileContainer_MDMProfiles alloc] initWithManagedConfig:managedConfig queue:self.device.workQueue]];
    }];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForSpringboardIconLayout
{
  return [[self.device
    startService:FBSpringboardServiceName]
    onQueue:self.device.asyncQueue pend:^ FBFuture<id<FBFileContainer>> * (FBAMDServiceConnection *connection) {
      return [FBFuture futureWithResult:[[FBSpringboardServicesClient springboardServicesClientWithConnection:connection logger:self.device.logger] iconContainer]];
    }];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForWallpaper
{
  return [[FBFutureContext
    futureContextWithFutureContexts:@[
      [self.device startService:FBSpringboardServiceName],
      [self.device startService:FBManagedConfigService],
    ]]
    onQueue:self.device.asyncQueue pend:^ FBFuture<id<FBFileContainer>> * (NSArray<FBAMDServiceConnection *> *connections) {
      FBSpringboardServicesClient *springboard = [FBSpringboardServicesClient springboardServicesClientWithConnection:connections[0] logger:self.device.logger];
      FBManagedConfigClient *managedConfig = [FBManagedConfigClient managedConfigClientWithConnection:connections[1] logger:self.device.logger];
      return [FBFuture futureWithResult:[[FBDeviceFileContainer_Wallpaper alloc] initWithSpringboard:springboard managedConfig:managedConfig queue:self.device.workQueue]];
    }];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForDiskImages
{
  return [FBFutureContext futureContextWithResult:[[FBDeviceFileCommands_DiskImages alloc] initWithCommands:self.device queue:self.device.asyncQueue]];
}

- (FBFutureContext<id<FBFileContainer>> *)fileCommandsForSymbols
{
  return [FBFutureContext futureContextWithResult:[[FBDeviceFileCommands_Symbols alloc] initWithCommands:self.device queue:self.device.asyncQueue]];
}

@end
