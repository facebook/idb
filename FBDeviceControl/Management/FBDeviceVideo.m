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

@interface FBDeviceVideo () <AVCaptureFileOutputRecordingDelegate>

@property (nonatomic, copy, readonly) NSString *filePath;
@property (nonatomic, strong, readonly) AVCaptureSession *session;
@property (nonatomic, strong, readonly) AVCaptureMovieFileOutput *output;
@property (nonatomic, strong, nullable, readonly) id<FBControlCoreLogger> logger;

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

+ (nullable instancetype)videoForDevice:(FBDevice *)device filePath:(NSString *)filePath error:(NSError **)error
{
  id<FBControlCoreLogger> logger = device.logger;
  NSError *innerError = nil;

  // Allow Access
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
  // Add the Output to the Session.
  AVCaptureMovieFileOutput *output = [[AVCaptureMovieFileOutput alloc] init];
  if (![session canAddOutput:output]) {
    return [[FBDeviceControlError
      describeFormat:@"Cannot add File Output to session for %@", captureDevice]
      fail:error];
  }
  [session addOutput:output];

  // Construct the Device Video instance.
  return [[FBDeviceVideo alloc] initWithFilePath:filePath captureSession:session output:output logger:logger];
}

- (instancetype)initWithFilePath:(NSString *)filePath captureSession:(AVCaptureSession *)session output:(AVCaptureMovieFileOutput *)output logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _filePath = filePath;
  _session = session;
  _output = output;
  _logger = logger;

  return self;
}

#pragma mark Public Methods

- (BOOL)startRecordingWithError:(NSError **)error
{
  NSError *innerError = nil;
  if ([NSFileManager.defaultManager fileExistsAtPath:self.filePath] && ![NSFileManager.defaultManager removeItemAtPath:self.filePath error:&innerError]) {
    return [[[FBDeviceControlError
      describeFormat:@"Failed to remove existing device video at %@", self.filePath]
      causedBy:innerError]
      failBool:error];
  }
  if (![NSFileManager.defaultManager createDirectoryAtPath:self.filePath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&innerError]) {
    return [[[FBDeviceControlError
      describeFormat:@"Failed to remove create auxillary directory for device at %@", self.filePath]
      causedBy:innerError]
      failBool:error];
  }
  NSURL *file = [NSURL fileURLWithPath:self.filePath];
  [self.session startRunning];
  [self.output startRecordingToOutputFileURL:file recordingDelegate:self];
  [self.logger logFormat:@"Started Video Session for Device Video at file %@", self.filePath];
  return YES;
}

- (BOOL)stopRecordingWithError:(NSError **)error
{
  [self.output stopRecording];
  [self.session stopRunning];
  return YES;
}

#pragma mark Recording Delegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
  [self.logger logFormat:@"Did Start Recording at %@", self.filePath];
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didPauseRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
  [self.logger logFormat:@"Did Pause Recording at %@", self.filePath];
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
  [self.logger logFormat:@"Did Finish Recording at %@", self.filePath];
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didResumeRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
  [self.logger logFormat:@"Did Resume Recording at %@", self.filePath];
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput willFinishRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
  [self.logger logFormat:@"Will Finish Recording at %@", self.filePath];
}

@end
