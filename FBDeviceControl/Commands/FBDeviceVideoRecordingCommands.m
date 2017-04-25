/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDeviceVideoRecordingCommands.h"

#import <FBControlCore/FBControlCore.h>

#import "FBDeviceVideo.h"
#import "FBDevice.h"
#import "FBDevice+Private.h"
#import "FBDeviceControlError.h"
#import "FBDeviceBitmapStream.h"

@interface FBDeviceVideoRecordingCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;
@property (nonatomic, strong, nullable, readwrite) FBDeviceVideo *video;

@end

@implementation FBDeviceVideoRecordingCommands

#pragma mark Initializers

+ (instancetype)commandsWithDevice:(FBDevice *)device
{
  return [[self alloc] initWithDevice:device];
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

#pragma mark FBVideoRecordingCommands

- (nullable id<FBVideoRecordingSession>)startRecordingToFile:(NSString *)filePath error:(NSError **)error
{
  NSError *innerError = nil;
  if (self.video) {
    return [[FBDeviceControlError
      describe:@"Cannot create a new video recording session, one is already active"]
      fail:error];
  }

  FBDiagnosticBuilder *logBuilder = [FBDiagnosticBuilder builderWithDiagnostic:self.device.diagnostics.video];
  filePath = filePath ?: logBuilder.createPath;
  self.video = [FBDeviceVideo videoForDevice:self.device filePath:filePath error:&innerError];
  if (!self.video) {
    return [FBDeviceControlError failWithError:innerError errorOut:error];
  }
  if (![self.video startRecordingWithError:error]) {
    return nil;
  }
  return self.video;
}

- (BOOL)stopRecordingWithError:(NSError **)error
{
  if (!self.video) {
    return [[FBDeviceControlError
      describeFormat:@"There was no existing video instance for %@", self.device]
      failBool:error];
  }
  return [self.video stopRecordingWithError:error];
}

#pragma mark FBBitmapStreamingCommands

- (nullable id<FBBitmapStream>)createStreamWithConfiguration:(FBBitmapStreamConfiguration *)configuration error:(NSError **)error
{
  AVCaptureSession *session = [FBDeviceVideo captureSessionForDevice:self.device error:error];
  if (!session) {
    return nil;
  }
  return [FBDeviceBitmapStream streamWithSession:session encoding:configuration.encoding logger:self.device.logger error:error];
}


@end
