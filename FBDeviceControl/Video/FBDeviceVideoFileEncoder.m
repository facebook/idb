/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDeviceVideoFileEncoder.h"

#import <FBControlCore/FBControlCore.h>
#import <AVFoundation/AVFoundation.h>

#import "FBDeviceControlError.h"

@interface FBDeviceVideoFileEncoder () <AVCaptureFileOutputRecordingDelegate>

@property (nonatomic, strong, readonly) AVCaptureSession *session;
@property (nonatomic, strong, readonly) AVCaptureMovieFileOutput *output;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, copy, readonly) NSString *filePath;

@end

@implementation FBDeviceVideoFileEncoder

+ (nullable instancetype)encoderWithSession:(AVCaptureSession *)session filePath:(NSString *)filePath logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  // Add the Output to the Session.
  AVCaptureMovieFileOutput *output = [[AVCaptureMovieFileOutput alloc] init];
  if (![session canAddOutput:output]) {
    return [[FBDeviceControlError
      describeFormat:@"Cannot add File Output to session for %@", filePath]
      fail:error];
  }
  [session addOutput:output];

  return [[FBDeviceVideoFileEncoder alloc] initWithSession:session output:output filePath:filePath logger:logger];
}

- (instancetype)initWithSession:(AVCaptureSession *)session output:(AVCaptureMovieFileOutput *)output filePath:(NSString *)filePath logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _session = session;
  _output = output;
  _filePath = filePath;
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
