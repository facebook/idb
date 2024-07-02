/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceDeveloperDiskImageCommands.h"

#import "FBAMDServiceConnection.h"
#import "FBDevice.h"
#import "FBDeviceControlError.h"

static NSString *const MountPathKey = @"MountPath";
static NSString *const ImageTypeKey = @"ImageType";
static NSString *const ImageSignatureKey = @"ImageSignature";
static NSString *const CommandKey = @"Command";

static NSString *const DiskImageTypeDeveloper = @"Developer";
static NSString *const ImageMounterService = @"com.apple.mobile.mobile_image_mounter";

static void MountCallback(NSDictionary<NSString *, id> *callbackDictionary, id<FBDeviceCommands> device)
{
  [device.logger logFormat:@"Mount Progress: %@", [FBCollectionInformation oneLineDescriptionFromDictionary:callbackDictionary]];
}

@interface FBDeviceDeveloperDiskImageCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;

@end

@implementation FBDeviceDeveloperDiskImageCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(FBDevice *)target
{
  return [[self alloc] initWithDevice:target];
}

- (instancetype)initWithDevice:(FBDevice *)device
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;

  return self;
}

#pragma mark FBDeveloperDiskImageCommands Implementation

static const int DiskImageMountingError = -402653066;  // 0xe8000076 in hex

- (FBFuture<NSArray<FBDeveloperDiskImage *> *> *)mountedDiskImages
{
  return [[self
    mountInfoToDiskImage]
    onQueue:self.device.asyncQueue map:^(NSDictionary<NSDictionary<NSString *, id> *, FBDeveloperDiskImage *> *mountInfoToDiskImage) {
      return [mountInfoToDiskImage allValues];
    }];
}

- (FBFuture<FBDeveloperDiskImage *> *)mountDiskImage:(FBDeveloperDiskImage *)diskImage
{
  return [self mountDeveloperDiskImage:diskImage imageType:DiskImageTypeDeveloper];
}

- (FBFuture<NSNull *> *)unmountDiskImage:(FBDeveloperDiskImage *)diskImage
{
  return [[self
    mountedImageEntries]
    onQueue:self.device.workQueue fmap:^ FBFuture<NSNull *> * (NSArray<NSDictionary<NSString *, id> *> *mountEntries) {
      for (NSDictionary<NSString *, id> *mountEntry in mountEntries) {
        NSData *mountSingature = mountEntry[ImageSignatureKey];
        if (![mountSingature isEqualToData:diskImage.signature]) {
          continue;
        }
        NSString *mountPath = mountEntry[MountPathKey];
        return [self unmountDiskImageAtPath:mountPath];
      }
      return [[FBDeviceControlError
        describeFormat:@"%@ does not appear to be mounted", diskImage]
        failFuture];
    }];
}

- (NSArray<FBDeveloperDiskImage *> *)mountableDiskImages
{
  return [FBDeveloperDiskImage allDiskImages: self.device.platformRootDirectory];
}

- (FBFuture<FBDeveloperDiskImage *> *)ensureDeveloperDiskImageIsMounted
{
  NSError *error = nil;
  NSOperatingSystemVersion targetVersion = [FBOSVersion operatingSystemVersionFromName:self.device.productVersion];
  FBDeveloperDiskImage *diskImage = [FBDeveloperDiskImage developerDiskImage:targetVersion logger:self.device.logger platformRootDirectory: self.device.platformRootDirectory error:&error];
  if (!diskImage) {
    return [FBFuture futureWithError:error];
  }
  return [self mountDeveloperDiskImage:diskImage imageType:DiskImageTypeDeveloper];
}

#pragma mark Private

- (FBFuture<NSDictionary<NSDictionary<NSString *, id> *, FBDeveloperDiskImage *> *> *)mountInfoToDiskImage
{
  id<FBControlCoreLogger> logger = self.device.logger;
  return [[self
    mountedImageEntries]
    onQueue:self.device.asyncQueue map:^(NSArray<NSDictionary<NSString *,id> *> *mountEntries) {
      NSArray<FBDeveloperDiskImage *> *images = [FBDeveloperDiskImage allDiskImages: self.device.platformRootDirectory];
      NSDictionary<NSData *, FBDeveloperDiskImage *> *imagesBySignature = [NSDictionary dictionaryWithObjects:images forKeys:[images valueForKey:@"signature"]];
      NSMutableDictionary<NSDictionary<NSString *, id> *, FBDeveloperDiskImage *> *mountEntryToDiskImage = NSMutableDictionary.dictionary;
      for (NSDictionary<NSString *, id> *mountEntry in mountEntries) {
        NSData *signature = mountEntry[ImageSignatureKey];
        FBDeveloperDiskImage *image = imagesBySignature[signature];
        if (!image) {
          [logger logFormat:@"Could not find the location of the image mounted on the device %@", mountEntryToDiskImage];
          image = [FBDeveloperDiskImage unknownDiskImageWithSignature:signature];
        }
        mountEntryToDiskImage[mountEntry] = image;
      }
      return [mountEntryToDiskImage copy];
    }];
}

- (FBFuture<NSArray<NSDictionary<NSString *, id> *> *> *)mountedImageEntries
{
  return [[self.device
    startService:ImageMounterService]
    onQueue:self.device.asyncQueue pop:^(FBAMDServiceConnection *connection) {
      NSDictionary<NSString *, id> *request = @{
        CommandKey: @"CopyDevices",
      };
      NSError *error = nil;
      NSDictionary<NSString *, id> *response = [connection sendAndReceiveMessage:request error:&error];
      if (!response) {
        return [FBFuture futureWithError:error];
      }
      NSString *errorString = response[@"Error"];
      if (errorString) {
        return [[FBDeviceControlError
          describeFormat:@"Could not get mounted image info: %@", errorString]
          failFuture];
      }
      NSArray<NSDictionary<NSString *, id> *> *entries = response[@"EntryList"];
      return [FBFuture futureWithResult:entries];
    }];
}

- (FBFuture<NSDictionary<NSData *, FBDeveloperDiskImage *> *> *)signatureToDiskImageOfMountedDisks
{
  return [[self
    mountInfoToDiskImage]
    onQueue:self.device.asyncQueue map:^(NSDictionary<NSDictionary<NSString *, id> *, FBDeveloperDiskImage *> *mountInfoToDiskImage) {
      NSMutableDictionary<NSData *, FBDeveloperDiskImage *> *signatureToDiskImage = NSMutableDictionary.dictionary;
      for (FBDeveloperDiskImage *image in mountInfoToDiskImage.allValues) {
        signatureToDiskImage[image.signature] = image;
      }
      return signatureToDiskImage;
    }];
}

- (FBFuture<FBDeveloperDiskImage *> *)mountDeveloperDiskImage:(FBDeveloperDiskImage *)diskImage imageType:(NSString *)imageType
{
  id<FBControlCoreLogger> logger = self.device.logger;
  return [[self
    signatureToDiskImageOfMountedDisks]
    onQueue:self.device.asyncQueue fmap:^ FBFuture<FBDeveloperDiskImage *> * (NSDictionary<NSData *, FBDeveloperDiskImage *> *signatureToDiskImage) {
      if (signatureToDiskImage[diskImage.signature]) {
        [logger logFormat:@"Disk Image %@ is already mounted, avoiding re-mounting it", diskImage];
        return [FBFuture futureWithResult:diskImage];
      }
      return [self performDiskImageMount:diskImage imageType:imageType];
    }];
}

- (FBFuture<FBDeveloperDiskImage *> *)performDiskImageMount:(FBDeveloperDiskImage *)diskImage imageType:(NSString *)imageType
{
  return [[self.device
    connectToDeviceWithPurpose:@"mount_disk_image"]
    onQueue:self.device.asyncQueue pop:^ FBFuture<NSDictionary<NSString *, NSDictionary<NSString *, id> *> *> * (id<FBDeviceCommands> device) {
      NSDictionary<NSString *, id> *options = @{
        ImageSignatureKey: diskImage.signature,
        ImageTypeKey: imageType,
      };
      int status = device.calls.MountImage(
        device.amDeviceRef,
        (__bridge CFStringRef)(diskImage.diskImagePath),
        (__bridge CFDictionaryRef)(options),
        (AMDeviceProgressCallback) MountCallback,
        (__bridge void *) (device)
      );
      if (status == DiskImageMountingError) {
        return [[FBDeviceControlError
          describeFormat:@"Failed to mount image '%@', this can occur when the wrong disk image is mounted for the target OS, or a disk image of the same type is already mounted.", diskImage]
          failFuture];
      }
      else if (status != 0) {
        NSString *internalMessage = CFBridgingRelease(device.calls.CopyErrorText(status));
        return [[FBDeviceControlError
          describeFormat:@"Failed to mount image '%@' with error 0x%x (%@)", diskImage.diskImagePath, status, internalMessage]
          failFuture];
      }
      return [FBFuture futureWithResult:diskImage];
    }];
}

- (FBFuture<NSNull *> *)unmountDiskImageAtPath:(NSString *)mountPath
{
  return [[self.device
    startService:ImageMounterService]
    onQueue:self.device.asyncQueue pop:^ FBFuture<NSNull *> * (FBAMDServiceConnection *connection) {
      NSDictionary<NSString *, id> *request = @{
        CommandKey: @"UnmountImage",
        MountPathKey: mountPath,
      };
      NSError *error = nil;
      NSDictionary<NSString *, id> *response = [connection sendAndReceiveMessage:request error:&error];
      if (!response) {
        return [FBFuture futureWithError:error];
      }
      return FBFuture.empty;
    }];
}

@end
