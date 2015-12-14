/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorVideoRecorder.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreMedia/CoreMedia.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorWindowHelpers.h"
#import "FBSimulatorWindowTiler.h"

@interface FBSimulatorVideoRecorder () <AVCaptureFileOutputRecordingDelegate, AVCaptureFileOutputDelegate>

@property (nonatomic, strong, readwrite) FBSimulator *simulator;
@property (nonatomic, strong, readwrite) id<FBSimulatorLogger> logger;

@property (nonatomic, copy, readwrite) NSString *filePath;
@property (nonatomic, copy, readwrite) NSURL *fileURL;
@property (nonatomic, strong, readwrite) AVCaptureSession *session;
@property (nonatomic, strong, readwrite) AVCaptureMovieFileOutput *output;

@end

@implementation FBSimulatorVideoRecorder

+ (instancetype)forSimulator:(FBSimulator *)simulator logger:(id<FBSimulatorLogger>)logger
{
  FBSimulatorVideoRecorder *recorder = [self new];
  recorder.simulator = simulator;
  recorder.logger = logger;
  return recorder;
}

- (BOOL)startRecordingToFilePath:(NSString *)filePath error:(NSError **)error
{
  if (self.session) {
    return [[[FBSimulatorError describe:@"Cannot Start Recording twice"] inSimulator:self.simulator] failBool:error];
  }

  CGRect cropRect = CGRectZero;
  CGDirectDisplayID displayID = [FBSimulatorWindowHelpers displayIDForSimulator:self.simulator cropRect:&cropRect screenSize:NULL];
  if (!displayID) {
    return [[[FBSimulatorError describe:@"Cannot obtain display ID for recording"] inSimulator:self.simulator] failBool:error];
  }

  NSError *innerError = nil;
  if ([NSFileManager.defaultManager fileExistsAtPath:filePath] && ![NSFileManager.defaultManager removeItemAtPath:filePath error:&innerError]) {
    return [[[FBSimulatorError describeFormat:@"Cannot remove existing video at '%@'", filePath] inSimulator:self.simulator] failBool:error];
  }
  self.filePath = filePath;
  self.fileURL = [NSURL fileURLWithPath:filePath];

  // Setup the Screen Capture Input
  AVCaptureScreenInput *input = [[AVCaptureScreenInput alloc] initWithDisplayID:displayID];
  if (!input) {
    return [[[FBSimulatorError describe:@"Could not Create Screen input for display id"] inSimulator:self.simulator] failBool:error];
  }
  input.cropRect = cropRect;

  // Then the Output
  AVCaptureMovieFileOutput *output = [[AVCaptureMovieFileOutput alloc] init];
  output.delegate = self;

  // Create & Setup the Session.
  AVCaptureSession *session = [[AVCaptureSession alloc] init];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(captureSessionDidStart:) name:AVCaptureSessionDidStartRunningNotification object:session];
  if (![session canAddInput:input]) {
    return [[[FBSimulatorError describe:@"Could not add AV Input to the Capture Sesion"] inSimulator:self.simulator] failBool:error];
  }
  [session addInput:input];
  if (![session canAddOutput:output]) {
    return [[[FBSimulatorError describe:@"Could not add AV Output to the Capture Sesion"] inSimulator:self.simulator] failBool:error];
  }
  [session addOutput:output];
  self.session = session;
  self.output = output;

  // The Session is started, but the recording to file isn't started *until* capture session starts.
  // This is because the Pixel Format changes when the Simulator hits Springboard, causing the File output to Terminate.
  // Instead of experiencing this termination, the file recording waits until the session is in a valid state.
  [session startRunning];

  return YES;
}

- (NSString *)stopRecordingWithError:(NSError **)error
{
  if (!self.session) {
    return [[FBSimulatorError describe:@"Cannot stop a Recording when one doesn't exist"] fail:error];
  }

  [self.output stopRecording];
  [self.session stopRunning];

  self.session = nil;
  self.output = nil;

  return self.filePath;
}

- (void)terminate
{
  [self stopRecordingWithError:nil];
}

- (void)dealloc
{
  [self terminate];
}

#pragma mark Notifications

- (void)captureSessionDidStart:(NSNotification *)notification
{
  [self.output startRecordingToOutputFileURL:self.fileURL recordingDelegate:self];
}

#pragma mark AVCaptureFileOutputRecordingDelegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didStartRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections;
{
  [self.logger logMessage:@"Capture started to %@", fileURL];
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didPauseRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections
{
  [self.logger logMessage:@"Capture paused at %@", fileURL];
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didResumeRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connection
{
  [self.logger logMessage:@"Capture resumed at %@", fileURL];
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput willFinishRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections error:(NSError *)error
{
  [self.logger logMessage:@"Will finish recording to %@", fileURL];
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput didFinishRecordingToOutputFileAtURL:(NSURL *)fileURL fromConnections:(NSArray *)connections error:(NSError *)error;
{
  [self.logger logMessage:@"Did finish recording to %@", fileURL];
}

- (BOOL)captureOutputShouldProvideSampleAccurateRecordingStart:(AVCaptureOutput *)captureOutput
{
  return NO;
}

@end
