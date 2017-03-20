/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDeviceBitmapStream.h"

#import <FBControlCore/FBControlCore.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>

#import "FBDeviceControlError.h"

static NSDictionary<NSString *, id> *FBBitmapStreamPixelBufferAttributesFromPixelBuffer(CVPixelBufferRef pixelBuffer);
static NSDictionary<NSString *, id> *FBBitmapStreamPixelBufferAttributesFromPixelBuffer(CVPixelBufferRef pixelBuffer)
{
  size_t width = CVPixelBufferGetWidth(pixelBuffer);
  size_t height = CVPixelBufferGetHeight(pixelBuffer);
  size_t frameSize = CVPixelBufferGetDataSize(pixelBuffer);
  size_t rowSize = CVPixelBufferGetBytesPerRow(pixelBuffer);
  OSType pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
  NSString *pixelFormatString = (__bridge NSString *) UTCreateStringForOSType(pixelFormat);

  return @{
    @"width" : @(width),
    @"height" : @(height),
    @"row_size" : @(rowSize),
    @"frame_size" : @(frameSize),
    @"format" : pixelFormatString,
  };
}

@interface FBDeviceBitmapStream () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) AVCaptureSession *session;
@property (nonatomic, strong, readonly) AVCaptureVideoDataOutput *output;
@property (nonatomic, strong, readonly) dispatch_queue_t writeQueue;
@property (nonatomic, strong, nullable, readwrite) id<FBFileConsumer> consumer;
@property (nonatomic, copy, nullable, readwrite) NSDictionary<NSString *, id> *pixelBufferAttributes;

@end

@implementation FBDeviceBitmapStream

+ (instancetype)streamWithSession:(AVCaptureSession *)session logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  // Create the output.
  AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
  output.alwaysDiscardsLateVideoFrames = YES;
  output.videoSettings = FBDeviceBitmapStream.videoSettings;
  if (![session canAddOutput:output]) {
    return [[FBDeviceControlError
      describe:@"Cannot add Data Output to session"]
      fail:error];
  }
  [session addOutput:output];

  // Create a serial queue to handle processing of frames
  dispatch_queue_t writeQueue = dispatch_queue_create("com.facebook.fbdevicecontrol.streamencoder", NULL);
  return [[self alloc] initWithSession:session output:output writeQueue:writeQueue logger:logger];
}

- (instancetype)initWithSession:(AVCaptureSession *)session output:(AVCaptureVideoDataOutput *)output writeQueue:(dispatch_queue_t)writeQueue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _session = session;
  _output = output;
  _writeQueue = writeQueue;
  _logger = logger;

  return self;
}

#pragma mark Public Methods

- (nullable FBBitmapStreamAttributes *)streamAttributesWithError:(NSError **)error
{
  NSDictionary<NSString *, id> *attributes = self.pixelBufferAttributes;
  if (!attributes) {
    return [[FBDeviceControlError
      describe:@"Could not obtain stream attributes"]
      fail:error];
  }
  return [[FBBitmapStreamAttributes alloc] initWithAttributes:attributes];
}

- (BOOL)startStreaming:(id<FBFileConsumer>)consumer error:(NSError **)error
{
  if (self.consumer) {
    return [[FBDeviceControlError
      describe:@"Cannot start streaming, a consumer is already attached"]
      failBool:error];
  }
  self.consumer = consumer;
  [self.output setSampleBufferDelegate:self queue:self.writeQueue];
  [self.session startRunning];
  return YES;
}

- (BOOL)stopStreamingWithError:(NSError **)error
{
  if (!self.consumer) {
    return [[FBDeviceControlError
      describe:@"Cannot stop streaming, no consumer attached"]
      failBool:error];
  }
  [self.session stopRunning];
  return YES;
}

+ (NSDictionary *)videoSettings
{
  return @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
}

#pragma mark AVCaptureAudioDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
  CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
  CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

  void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
  size_t size = CVPixelBufferGetDataSize(pixelBuffer);
  NSData *data = [NSData dataWithBytesNoCopy:baseAddress length:size freeWhenDone:NO];
  [self.consumer consumeData:data];

  CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

  if (!self.pixelBufferAttributes) {
    NSDictionary<NSString *, id> *attributes = FBBitmapStreamPixelBufferAttributesFromPixelBuffer(pixelBuffer);
    self.pixelBufferAttributes = attributes;
    [self.logger logFormat:@"Mounting Surface with Attributes: %@", attributes];
  }
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
}

#pragma mark FBTerminationHandle

- (FBTerminationHandleType)type
{
  return FBTerminationHandleTypeVideoStreaming;
}

- (void)terminate
{
  [self stopStreamingWithError:nil];
}

@end
