/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceFileCommands.h"

#import "FBAFCConnection.h"
#import "FBDevice+Private.h"
#import "FBDevice.h"
#import "FBDeviceControlError.h"
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

- (FBFuture<NSNull *> *)copyFromHost:(NSURL *)sourcePath toContainer:(NSString *)destinationPath
{
  return [self handleAFCOperation:^ NSNull * (FBAFCConnection *afc, NSError **error) {
    BOOL success = [afc copyFromHost:sourcePath toContainerPath:destinationPath error:error];
    if (!success) {
      return nil;
    }
    return NSNull.null;
  }];
}

- (FBFuture<NSString *> *)copyFromContainer:(NSString *)containerPath toHost:(NSString *)destinationPath
{
  return [[self
    readFileFromPathInContainer:containerPath]
    onQueue:self.queue fmap:^FBFuture<NSString *> *(NSData *fileData) {
     NSError *error;
     if (![fileData writeToFile:destinationPath options:0 error:&error]) {
       return [[[FBDeviceControlError
        describeFormat:@"Failed to write data to file at path %@", destinationPath]
        causedBy:error]
        failFuture];
     }
     return [FBFuture futureWithResult:destinationPath];
   }];
}

- (FBFuture<FBFuture<NSNull *> *> *)tail:(NSString *)containerPath toConsumer:(id<FBDataConsumer>)consumer
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

- (FBFuture<NSString *> *)copyFromContainer:(NSString *)containerPath toHost:(NSString *)destinationPath
{
  return [[self.springboard
    wallpaperImageDataForKind:containerPath.lastPathComponent]
    onQueue:self.queue fmap:^ FBFuture<NSString *> * (NSData *data) {
      NSError *error = nil;
      if (![data writeToFile:destinationPath options:NSDataWritingAtomic error:&error]) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:destinationPath];
    }];
}

- (FBFuture<NSNull *> *)copyFromHost:(NSURL *)sourcePath toContainer:(NSString *)destinationPath
{
  return [FBFuture
    onQueue:self.queue resolve:^ FBFuture<NSNull *> * {
      NSError *error = nil;
      NSData *data = [NSData dataWithContentsOfURL:sourcePath options:0 error:&error];
      if (!data) {
        return [FBFuture futureWithError:error];
      }
      return [self.managedConfig changeWallpaperWithName:destinationPath.lastPathComponent data:data];
    }];
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

- (FBFuture<NSString *> *)copyFromContainer:(NSString *)containerPath toHost:(NSString *)destinationPath
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not make sense for MDM Profile File Containers", NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)copyFromHost:(NSURL *)sourcePath toContainer:(NSString *)destinationPath
{
  return [FBFuture
    onQueue:self.queue resolve:^ FBFuture<NSNull *> * {
      NSError *error = nil;
      NSData *data = [NSData dataWithContentsOfURL:sourcePath options:0 error:&error];
      if (!data) {
        return [FBFuture futureWithError:error];
      }
      return [self.managedConfig installProfile:data];
    }];
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

static NSString *const MountedDeveloperDirectory = @"Developer";

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

- (FBFuture<NSNull *> *)copyFromHost:(NSURL *)sourcePath toContainer:(NSString *)destinationPath
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not make sense for Disk Images", NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSString *> *)copyFromContainer:(NSString *)containerPath toHost:(NSString *)destinationPath
{
  return [[FBControlCoreError
    describeFormat:@"%@ does not make sense for Disk Images", NSStringFromSelector(_cmd)]
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
    describeFormat:@"%@ does not make sense for Disk Images", NSStringFromSelector(_cmd)]
    failFuture];
}

- (FBFuture<NSNull *> *)moveFrom:(NSString *)sourcePath to:(NSString *)destinationPath
{
  if (![destinationPath hasPrefix:MountedDeveloperDirectory]) {
    return [[FBDeviceControlError
      describeFormat:@"%@ only mounts can be moved", destinationPath]
      failFuture];
  }
  NSArray<FBDeveloperDiskImage *> *images = self.commands.availableDeveloperDiskImages;
  NSDictionary<NSString *, FBDeveloperDiskImage *> *imagesByPath = [NSDictionary dictionaryWithObjects:images forKeys:[images valueForKey:@"diskImagePath"]];
  FBDeveloperDiskImage *image = imagesByPath[sourcePath];
  if (!image) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not one of %@", sourcePath, [FBCollectionInformation oneLineDescriptionFromArray:images]]
      failFuture];
  }
  return [[self.commands
    mountDeveloperDiskImage:image]
    mapReplace:NSNull.null];
}

- (FBFuture<NSNull *> *)remove:(NSString *)path
{
  if (![path hasPrefix:MountedDeveloperDirectory]) {
    return [[FBDeviceControlError
      describeFormat:@"%@ cannot be removed, only mounts can be removed", path]
      failFuture];
  }
  return [[self.commands
    unmountDeveloperDiskImage]
    mapReplace:NSNull.null];
}

- (FBFuture<NSArray<NSString *> *> *)contentsOfDirectory:(NSString *)path
{
  if ([path isEqualToString:MountedDeveloperDirectory]) {
    return [[self.commands
      mountedDeveloperDiskImage]
      onQueue:self.queue map:^(FBDeveloperDiskImage *image) {
        return @[image.diskImagePath];
      }];
  }
  return [[self.commands
    mountedDeveloperDiskImage]
    onQueue:self.queue chain:^(FBFuture *result) {
      NSMutableArray<NSString *> *images = [[self.commands.availableDeveloperDiskImages valueForKey:@"diskImagePath"] mutableCopy];
      if (result.result) {
        [images addObject:MountedDeveloperDirectory];
      }
      return [FBFuture futureWithResult:images];
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

@end
