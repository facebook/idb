/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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

@end

@implementation FBDeviceVideo

#pragma mark Initialization Helpers

+ (nullable AVCaptureDevice *)findCaptureDeviceForDevice:(FBDevice *)device error:(NSError **)error
{
  // Sometimes, especially on first launch the AVCaptureDevice may take a while to come up, we should wait for it.
  AVCaptureDevice *captureDevice = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout untilExists:^{
    return [AVCaptureDevice deviceWithUniqueID:device.udid];
  }];
  if (!captureDevice) {
    return [[FBDeviceControlError
      describeFormat:@"Could not find Capture Device for %@ in %@", device, [FBCollectionInformation oneLineDescriptionFromArray:AVCaptureDevice.devices]]
      fail:error];
  }
  return captureDevice;
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

+ (nullable AVCaptureSession *)captureSessionForDevice:(FBDevice *)device error:(NSError **)error
{
  // Allow Access
  NSError *innerError = nil;
  if (![self allowAccessToScreenCaptureDevicesWithError:&innerError]) {
    return [FBDeviceControlError failWithError:innerError errorOut:error];
  }
  // Obtain the Capture Device
  AVCaptureDevice *captureDevice = [self findCaptureDeviceForDevice:device error:&innerError];
  if (!captureDevice) {
    return [FBDeviceControlError failWithError:innerError errorOut:error];
  }
  // Get the Input instance for this Device.
  AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:captureDevice error:&innerError];
  if (!deviceInput) {
    return [[[FBDeviceControlError
      describeFormat:@"Failed to create Device Input for %@", captureDevice]
      causedBy:innerError]
      fail:error];
  }
  // Add the Input to a new Session.
  AVCaptureSession *session = [[AVCaptureSession alloc] init];
  if (![session canAddInput:deviceInput]) {
    return [[FBDeviceControlError
      describeFormat:@"Cannot add Device Input to session for %@", captureDevice]
      fail:error];
  }
  [session addInput:deviceInput];

  return session;
}

+ (nullable instancetype)videoForDevice:(FBDevice *)device filePath:(NSString *)filePath error:(NSError **)error
{
  // Add the Input to a new Session.
  NSError *innerError = nil;
  AVCaptureSession *session = [self captureSessionForDevice:device error:&innerError];
  if (!session) {
    return [FBDeviceControlError failWithError:innerError errorOut:error];
  }

  // Construct the Device Video instance.
  FBDeviceVideoFileEncoder *encoder = [FBDeviceVideoFileEncoder encoderWithSession:session filePath:filePath logger:device.logger error:&innerError];
  if (!encoder) {
    return [FBDeviceControlError failWithError:innerError errorOut:error];
  }
  return [[FBDeviceVideo alloc] initWithEncoder:encoder];
}

- (instancetype)initWithEncoder:(FBDeviceVideoFileEncoder *)encoder
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _encoder = encoder;

  return self;
}

- (BOOL)startRecordingWithError:(NSError **)error
{
  return [self.encoder startRecordingWithError:error];
}

- (BOOL)stopRecordingWithError:(NSError **)error
{
  return [self.encoder stopRecordingWithError:error];
}

#pragma mark FBTerminationHandle

- (FBTerminationHandleType)type
{
  return FBTerminationTypeHandleVideoRecording;
}

- (void)terminate
{
  [self.encoder stopRecordingWithError:nil];
}

@end
