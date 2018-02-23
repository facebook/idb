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

+ (instancetype)commandsWithTarget:(FBDevice *)device
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

- (FBFuture<id<FBVideoRecordingSession>> *)startRecordingToFile:(NSString *)filePath
{
  if (self.video) {
    return [[FBDeviceControlError
      describe:@"Cannot create a new video recording session, one is already active"]
      failFuture];
  }

  FBDiagnosticBuilder *logBuilder = [FBDiagnosticBuilder builderWithDiagnostic:self.device.diagnostics.video];
  filePath = filePath ?: logBuilder.createPath;

  return [[FBDeviceVideo
    videoForDevice:self.device filePath:filePath]
    onQueue:self.device.workQueue fmap:^(FBDeviceVideo *video) {
      self.video = video;
      return [[video startRecording] mapReplace:video];
    }];
}

- (FBFuture<NSNull *> *)stopRecording
{
  if (!self.video) {
    return [[FBDeviceControlError
      describeFormat:@"There was no existing video instance for %@", self.device]
      failFuture];
  }
  return [self.video stopRecording];
}

#pragma mark FBBitmapStreamingCommands

- (FBFuture<id<FBBitmapStream>> *)createStreamWithConfiguration:(FBBitmapStreamConfiguration *)configuration
{
  return [[FBDeviceVideo
    captureSessionForDevice:self.device]
    onQueue:self.device.workQueue fmap:^(AVCaptureSession *session) {
      NSError *error = nil;
      FBDeviceBitmapStream *stream = [FBDeviceBitmapStream streamWithSession:session encoding:configuration.encoding logger:self.device.logger error:&error];
      if (!stream) {
        return [FBFuture futureWithError:error];
      }
      return [FBFuture futureWithResult:stream];
    }];
}

@end
