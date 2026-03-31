/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBVideoFileWriter.h"

#import <AVFoundation/AVFoundation.h>

#import <FBControlCore/FBControlCore.h>

#import "FBControlCoreError.h"

@interface FBVideoFileWriter () <AVCaptureFileOutputRecordingDelegate>

@property (nonatomic, readonly, strong) AVCaptureSession *session;
@property (nonatomic, readonly, strong) AVCaptureMovieFileOutput *output;
@property (nonatomic, readonly, strong) id<FBControlCoreLogger> logger;
@property (nonatomic, readonly, strong) FBMutableFuture<NSNull *> *startFuture;
@property (nonatomic, readonly, strong) FBMutableFuture<NSNull *> *finishFuture;
@property (nonatomic, readonly, copy) NSString *filePath;

@end

@implementation FBVideoFileWriter

+ (nullable instancetype)writerWithSession:(AVCaptureSession *)session filePath:(NSString *)filePath logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  // Add the Output to the Session.
  AVCaptureMovieFileOutput *output = [[AVCaptureMovieFileOutput alloc] init];
  if (![session canAddOutput:output]) {
    return [[FBControlCoreError
             describe:[NSString stringWithFormat:@"Cannot add File Output to session for %@", filePath]]
            fail:error];
  }
  [session addOutput:output];

  return [[FBVideoFileWriter alloc] initWithSession:session output:output filePath:filePath logger:logger];
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
  _startFuture = FBMutableFuture.future;
  _finishFuture = FBMutableFuture.future;

  return self;
}

#pragma mark Public Methods

- (FBFuture<NSNull *> *)startRecording
{
  NSError *innerError = nil;
  if ([NSFileManager.defaultManager fileExistsAtPath:self.filePath]) {
    [self.logger log:[NSString stringWithFormat:@"File already exists at %@, deleting", self.filePath]];
    if (![NSFileManager.defaultManager removeItemAtPath:self.filePath error:&innerError]) {
      return [[[FBControlCoreError
                describe:[NSString stringWithFormat:@"Failed to remove existing device video at %@", self.filePath]]
               causedBy:innerError]
              failFuture];
    }
    [self.logger log:[NSString stringWithFormat:@"Removed video file at %@", self.filePath]];
  }
  if (![NSFileManager.defaultManager createDirectoryAtPath:self.filePath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&innerError]) {
    return [[[FBControlCoreError
              describe:[NSString stringWithFormat:@"Failed to remove create auxillary directory for device at %@", self.filePath]]
             causedBy:innerError]
            failFuture];
  }
  NSURL *file = [NSURL fileURLWithPath:self.filePath];
  [self.session startRunning];
  [self.output startRecordingToOutputFileURL:file recordingDelegate:self];
  [self.logger log:[NSString stringWithFormat:@"Started Video Session for Device Video at file %@", self.filePath]];
  return self.startFuture;
}

- (FBFuture<NSNull *> *)stopRecording
{
  [self.output stopRecording];
  [self.session stopRunning];
  return self.finishFuture;
}

- (FBFuture<NSNull *> *)completed
{
  return self.finishFuture;
}

#pragma mark Recording Delegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
  [self.logger log:[NSString stringWithFormat:@"Did Start Recording at %@", self.filePath]];
  [self.startFuture resolveWithResult:NSNull.null];
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didPauseRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
  [self.logger log:[NSString stringWithFormat:@"Did Pause Recording at %@", self.filePath]];
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
  [self.logger log:[NSString stringWithFormat:@"Did Finish Recording at %@", self.filePath]];
  [self.finishFuture resolveWithResult:NSNull.null];
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didResumeRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
  [self.logger log:[NSString stringWithFormat:@"Did Resume Recording at %@", self.filePath]];
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput willFinishRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
  [self.logger log:[NSString stringWithFormat:@"Will Finish Recording at %@", self.filePath]];
}

@end
