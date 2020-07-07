/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
  NSString *pixelFormatString = (__bridge_transfer NSString *) UTCreateStringForOSType(pixelFormat);

  return @{
    @"width" : @(width),
    @"height" : @(height),
    @"row_size" : @(rowSize),
    @"frame_size" : @(frameSize),
    @"format" : pixelFormatString,
  };
}

@interface FBDeviceBitmapStream_BGRA : FBDeviceBitmapStream

@end

@interface FBDeviceBitmapStream_H264 : FBDeviceBitmapStream

@property (nonatomic, assign, readwrite) BOOL sentH264SPSPPS;

@end

@interface FBDeviceBitmapStream () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) AVCaptureSession *session;
@property (nonatomic, strong, readonly) AVCaptureVideoDataOutput *output;
@property (nonatomic, strong, readonly) dispatch_queue_t writeQueue;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *startFuture;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *stopFuture;

@property (nonatomic, strong, nullable, readwrite) id<FBDataConsumer> consumer;
@property (nonatomic, copy, nullable, readwrite) NSDictionary<NSString *, id> *pixelBufferAttributes;

@end

@implementation FBDeviceBitmapStream

+ (instancetype)streamWithSession:(AVCaptureSession *)session encoding:(FBBitmapStreamEncoding)encoding logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  // Create the output.
  AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
  output.alwaysDiscardsLateVideoFrames = YES;
  output.videoSettings = [FBDeviceBitmapStream videoSettingsForEncoding:encoding];
  if (![session canAddOutput:output]) {
    return [[FBDeviceControlError
      describe:@"Cannot add Data Output to session"]
      fail:error];
  }
  [session addOutput:output];

  // Create a serial queue to handle processing of frames
  dispatch_queue_t writeQueue = dispatch_queue_create("com.facebook.fbdevicecontrol.streamencoder", NULL);
  if ([encoding isEqualToString:FBBitmapStreamEncodingBGRA]) {
    return [[FBDeviceBitmapStream_BGRA alloc] initWithSession:session output:output writeQueue:writeQueue logger:logger];
  }
  if ([encoding isEqualToString:FBBitmapStreamEncodingH264]) {
    return [[FBDeviceBitmapStream_H264 alloc] initWithSession:session output:output writeQueue:writeQueue logger:logger];
  }
  return [[FBDeviceControlError
    describeFormat:@"%@ is not a valid stream encoding", encoding]
    fail:error];
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
  _startFuture = FBMutableFuture.future;
  _stopFuture = FBMutableFuture.future;

  return self;
}

#pragma mark Public Methods

- (FBFuture<FBBitmapStreamAttributes *> *)streamAttributes
{
  NSDictionary<NSString *, id> *dictionary = self.pixelBufferAttributes;
  if (!dictionary) {
    return [[FBDeviceControlError
      describe:@"Could not obtain stream attributes"]
      failFuture];
  }
  FBBitmapStreamAttributes *attributes = [[FBBitmapStreamAttributes alloc] initWithAttributes:dictionary];
  return [FBFuture futureWithResult:attributes];
}

- (FBFuture<NSNull *> *)startStreaming:(id<FBDataConsumer>)consumer
{
  if (self.consumer) {
    return [[FBDeviceControlError
      describe:@"Cannot start streaming, a consumer is already attached"]
      failFuture];
  }
  self.consumer = consumer;
  [self.output setSampleBufferDelegate:self queue:self.writeQueue];
  [self.session startRunning];
  return self.startFuture;
}

- (FBFuture<NSNull *> *)stopStreaming
{
  if (!self.consumer) {
    return [[FBDeviceControlError
      describe:@"Cannot stop streaming, no consumer attached"]
      failFuture];
  }
  [self.session stopRunning];
  [self.stopFuture resolveWithResult:NSNull.null];
  return self.stopFuture;
}

+ (NSDictionary<NSString *, id> *)videoSettingsForEncoding:(FBBitmapStreamEncoding)encoding
{
  if ([encoding isEqualToString:FBBitmapStreamEncodingBGRA]) {
    return @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
  }
  return @{};
}

#pragma mark AVCaptureAudioDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
  if (!self.consumer) {
    return;
  }
  [self.startFuture resolveWithResult:NSNull.null];
  [self consumeSampleBuffer:sampleBuffer];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
  [self.logger logFormat:@"Dropped a sample!"];
}

#pragma mark Data consumption

- (void)consumeSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

#pragma mark FBiOSTargetContinuation

- (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeVideoStreaming;
}

- (FBFuture<NSNull *> *)completed
{
  return [self.stopFuture onQueue:self.writeQueue respondToCancellation:^{
    return [self stopStreaming];
  }];
}

@end

@implementation FBDeviceBitmapStream_BGRA

- (void)consumeSampleBuffer:(CMSampleBufferRef)sampleBuffer
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

@end

@implementation FBDeviceBitmapStream_H264

- (void)consumeSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
  WriteFrameToAnnexBStream(sampleBuffer, self.consumer, self.logger, nil);
}

@end
