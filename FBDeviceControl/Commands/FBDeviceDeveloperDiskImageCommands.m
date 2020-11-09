/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceDeveloperDiskImageCommands.h"

#import "FBAMDServiceConnection.h"
#import "FBDevice.h"
#import "FBDeviceControlError.h"

static NSString *const DiskImageTypeDeveloper = @"Developer";
static NSString *const MountPathKey = @"MountPath";
static NSString *const CommandKey = @"Command";
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

static const int DiskImageAlreadyMountedCode = -402653066;  // 0xe8000076 in hex

- (FBFuture<FBDeveloperDiskImage *> *)ensureDiskImageIsMounted
{
  NSError *error = nil;
  NSOperatingSystemVersion targetVersion = [FBOSVersion operatingSystemVersionFromName:self.device.productVersion];
  FBDeveloperDiskImage *diskImage = [FBDeveloperDiskImage developerDiskImage:targetVersion logger:self.device.logger error:&error];
  if (!diskImage) {
    return [FBFuture futureWithError:error];
  }
  return [self mountDeveloperDiskImage:diskImage imageType:DiskImageTypeDeveloper failIfMounted:NO];
}

- (FBFuture<FBDeveloperDiskImage *> *)mountDeveloperDiskImage:(FBDeveloperDiskImage *)diskImage
{
  return [self mountDeveloperDiskImage:diskImage imageType:DiskImageTypeDeveloper failIfMounted:YES];
}

- (FBFuture<FBDeveloperDiskImage *> *)mountedDeveloperDiskImage
{
  return [[self
    entryForDiskImageType:DiskImageTypeDeveloper]
    onQueue:self.device.asyncQueue fmap:^(NSDictionary<NSString *, id> *entry) {
      NSData *signature = entry[@"ImageSignature"];
      NSArray<FBDeveloperDiskImage *> *images = FBDeveloperDiskImage.allDiskImages;
      NSDictionary<NSData *, FBDeveloperDiskImage *> *imagesBySignature = [NSDictionary dictionaryWithObjects:images forKeys:[images valueForKey:@"signature"]];
      FBDeveloperDiskImage *image = imagesBySignature[signature];
      if (!image) {
        return [[FBDeviceControlError
          describe:@"No disk image found for signature"]
          failFuture];
      }
      return [FBFuture futureWithResult:image];
    }];
}

- (NSArray<FBDeveloperDiskImage *> *)availableDeveloperDiskImages
{
  return FBDeveloperDiskImage.allDiskImages;
}

- (FBFuture<FBDeveloperDiskImage *> *)unmountDeveloperDiskImage
{
  return [[self
    mountPathForDiskImageType:DiskImageTypeDeveloper]
    onQueue:self.device.workQueue fmap:^(NSString *mountPath) {
      return [self unmountDiskImageAtPath:mountPath];
    }];
}

#pragma mark Private

- (FBFuture<NSString *> *)mountPathForDiskImageType:(NSString *)diskImageType
{
  return [[self
    entryForDiskImageType:DiskImageTypeDeveloper]
    onQueue:self.device.asyncQueue fmap:^(NSDictionary<NSString *, id> *entry) {
      NSString *mountPath = entry[MountPathKey];
      if (!mountPath) {
        return [[FBDeviceControlError
          describeFormat:@"No %@ in %@", MountPathKey, [FBCollectionInformation oneLineDescriptionFromDictionary:entry]]
          failFuture];
      }
      return [FBFuture futureWithResult:mountPath];
    }];
}

- (FBFuture<NSDictionary<NSString *, id> *> *)entryForDiskImageType:(NSString *)diskImageType
{
  return [[self
    entriesByDiskImageType]
    onQueue:self.device.asyncQueue fmap:^(NSDictionary<NSString *, NSDictionary<NSString *, id> *> *entriesByDiskImageType) {
      NSDictionary<NSString *, id> *entry = entriesByDiskImageType[diskImageType];
      if (!entry) {
        return [[FBDeviceControlError
          describeFormat:@"%@ is not one of %@", diskImageType, [FBCollectionInformation oneLineDescriptionFromDictionary:entriesByDiskImageType]]
          failFuture];
      }
      return [FBFuture futureWithResult:entry];
    }];
}

- (FBFuture<NSDictionary<NSString *, NSDictionary<NSString *, id> *> *> *)entriesByDiskImageType
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
      NSArray<NSDictionary<NSString *, id> *> *entryList = response[@"EntryList"];
      NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *entries = NSMutableDictionary.dictionary;
      for (NSDictionary<NSString *, id> *entry in entryList) {
        NSString *diskImageType = entry[@"DiskImageType"];
        if (!diskImageType) {
          continue;
        }
        entries[diskImageType] = entry;
      }
      return [FBFuture futureWithResult:entries];
    }];
}

- (FBFuture<FBDeveloperDiskImage *> *)mountDeveloperDiskImage:(FBDeveloperDiskImage *)diskImage imageType:(NSString *)imageType failIfMounted:(BOOL)failIfMounted
{
  return [[self.device
    connectToDeviceWithPurpose:@"mount_disk_image"]
    onQueue:self.device.asyncQueue pop:^ FBFuture<NSDictionary<NSString *, NSDictionary<NSString *, id> *> *> * (id<FBDeviceCommands> device) {
      NSDictionary<NSString *, id> *options = @{
        @"ImageSignature": diskImage.signature,
        @"ImageType": imageType,
      };
      int status = device.calls.MountImage(
        device.amDeviceRef,
        (__bridge CFStringRef)(diskImage.diskImagePath),
        (__bridge CFDictionaryRef)(options),
        (AMDeviceProgressCallback) MountCallback,
        (__bridge void *) (device)
      );
      if (status == DiskImageAlreadyMountedCode) {
        if (failIfMounted) {
          return [[FBDeviceControlError
            describeFormat:@"Failed to mount image '%@', a disk image is already mounted", diskImage]
            failFuture];
        }
        [device.logger logFormat:@"There is a disk image already mounted. Assuming that it is correct...."];
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
