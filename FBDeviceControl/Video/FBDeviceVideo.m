/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceVideo.h"

#import <FBControlCore/FBControlCore.h>

#import <AVFoundation/AVFoundation.h>

#import <CoreMediaIO/CMIOHardwareObject.h>
#import <CoreMediaIO/CMIOHardwareSystem.h>
#import <CoreFoundation/CoreFoundation.h>

#import "FBDevice.h"
#import "FBDeviceControlError.h"
#import "FBDeviceControlFrameworkLoader.h"
#import "FBDeviceVideoFileEncoder.h"

@interface FBDeviceVideo ()

@property (nonatomic, strong, readonly) FBDeviceVideoFileEncoder *encoder;
@property (nonatomic, strong, readonly) dispatch_queue_t workQueue;

@end

@implementation FBDeviceVideo

#pragma mark Initialization Helpers

+ (FBFuture<AVCaptureDevice *> *)findCaptureDeviceForDevice:(FBDevice *)device
{
  return [[FBFuture
    onQueue:device.workQueue resolveUntil:^{
      AVCaptureDevice *captureDevice = [AVCaptureDevice deviceWithUniqueID:device.udid];
      if (!captureDevice) {
        return [[[FBDeviceControlError
          describeFormat:@"Capture Device %@ not available", device.udid]
          noLogging]
          failFuture];
      }
      return [FBFuture futureWithResult:captureDevice];
    }]
    timeout:FBControlCoreGlobalConfiguration.fastTimeout waitingFor:@"Device %@ to have an associated capture device appear", device];
}

+ (BOOL)allowAccessToScreenCaptureDevicesWithError:(NSError **)error
{
  CMIOObjectPropertyAddress properties = {
    kCMIOHardwarePropertyAllowScreenCaptureDevices,
    kCMIOObjectPropertyScopeGlobal,
    kCMIOObjectPropertyElementMaster,
  };
  UInt32 allow = 1;
  OSStatus status = CMIOObjectSetPropertyData(
    kCMIOObjectSystemObject,
    &properties,
    0,
    NULL,
    sizeof(allow),
    &allow
  );
  if (status != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Failed to enable Screen Capture devices with status %d", status]
      failBool:error];
  }
  return YES;
}

#pragma mark Initializers

+ (FBFuture<AVCaptureSession *> *)captureSessionForDevice:(FBDevice *)device
{
  // Allow Access
  NSError *error = nil;
  if (![self allowAccessToScreenCaptureDevicesWithError:&error]) {
    return [FBFuture futureWithError:error];
  }
  // Obtain the Capture Device
  return [[self
    findCaptureDeviceForDevice:device]
    onQueue:device.workQueue fmap:^(AVCaptureDevice *captureDevice) {
      // Get the Input instance for this Device.
      NSError *innerError = nil;
      AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:captureDevice error:&innerError];
      if (!deviceInput) {
        return [[[FBDeviceControlError
          describeFormat:@"Failed to create Device Input for %@", captureDevice]
          causedBy:innerError]
          failFuture];
      }
      // Add the Input to a new Session.
      AVCaptureSession *session = [[AVCaptureSession alloc] init];
      if (![session canAddInput:deviceInput]) {
        return [[FBDeviceControlError
          describeFormat:@"Cannot add Device Input to session for %@", captureDevice]
          failFuture];
      }
      [session addInput:deviceInput];

      return [FBFuture futureWithResult:session];
    }];
}

+ (FBFuture<FBDeviceVideo *> *)videoForDevice:(FBDevice *)device filePath:(NSString *)filePath
{
  // Add the Input to a new Session.
  return [[self
    captureSessionForDevice:device]
    onQueue:device.workQueue fmap:^(AVCaptureSession *session) {
      // Construct the Device Video instance.
      NSError *error = nil;
      FBDeviceVideoFileEncoder *encoder = [FBDeviceVideoFileEncoder encoderWithSession:session filePath:filePath logger:device.logger error:&error];
      if (!encoder) {
        return [FBFuture futureWithError:error];
      }
      FBDeviceVideo *video = [[FBDeviceVideo alloc] initWithEncoder:encoder workQueue:device.workQueue];
      return [FBFuture futureWithResult:video];
    }];
}

- (instancetype)initWithEncoder:(FBDeviceVideoFileEncoder *)encoder workQueue:(dispatch_queue_t)workQueue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _encoder = encoder;
  _workQueue = workQueue;

  return self;
}

#pragma mark Public

- (FBFuture<NSNull *> *)startRecording
{
  return [self.encoder startRecording];
}

- (FBFuture<NSNull *> *)stopRecording
{
  return [self.encoder stopRecording];
}

#pragma mark FBiOSTargetContinuation

- (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeVideoRecording;
}

- (FBFuture<NSNull *> *)completed
{
  FBDeviceVideoFileEncoder *encoder = self.encoder;
  return [[encoder
    completed]
    onQueue:self.workQueue respondToCancellation:^{
      return [encoder stopRecording];
    }];
}

@end
