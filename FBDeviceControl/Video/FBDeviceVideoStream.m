/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceVideoStream.h"

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

@interface FBDeviceVideoStream_BGRA : FBDeviceVideoStream

@end

@interface FBDeviceVideoStream_H264 : FBDeviceVideoStream

@property (nonatomic, assign, readwrite) BOOL sentH264SPSPPS;

@end

@interface FBDeviceVideoStream () <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) AVCaptureSession *session;
@property (nonatomic, strong, readonly) AVCaptureVideoDataOutput *output;
@property (nonatomic, strong, readonly) dispatch_queue_t writeQueue;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *startFuture;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *stopFuture;

@property (nonatomic, strong, nullable, readwrite) id<FBDataConsumer, FBDataConsumerStackConsuming> consumer;
@property (nonatomic, copy, nullable, readwrite) NSDictionary<NSString *, id> *pixelBufferAttributes;

@end

@implementation FBDeviceVideoStream

+ (instancetype)streamWithSession:(AVCaptureSession *)session configuration:(FBVideoStreamConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  // Get the class to project into
  Class streamClass = [self classForEncoding:configuration.encoding];
  if (!streamClass) {
    return [[FBDeviceControlError
      describeFormat:@"%@ is not a valid stream encoding", configuration.encoding]
      fail:error];
  }
  // Create the output.
  AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
  if (![streamClass configureVideoOutput:output configuration:configuration error:error]) {
    return nil;
  }
  if (![session canAddOutput:output]) {
    return [[FBDeviceControlError
      describe:@"Cannot add Data Output to session"]
      fail:error];
  }
  [session addOutput:output];

  // Set the minimum duration between frames as a frame limiter
  if (configuration.framesPerSecond) {
    if (@available(macOS 10.15, *)) {
      AVCaptureConnection *connection = session.connections.firstObject;
      if (!connection) {
        return [[FBDeviceControlError
          describe:@"No capture connection available!"]
          fail:error];
      }
      Float64 frameTime = 1 / configuration.framesPerSecond.unsignedIntegerValue;
      connection.videoMinFrameDuration = CMTimeMakeWithSeconds(frameTime, NSEC_PER_SEC);
    } else {
      return [[FBDeviceControlError
        describeFormat:@"Cannot set FPS on an OS prior to 10.15"]
        fail:error];
    }
  }

  // Create a serial queue to handle processing of frames
  dispatch_queue_t writeQueue = dispatch_queue_create("com.facebook.fbdevicecontrol.streamencoder", NULL);
  return [[streamClass alloc] initWithSession:session output:output writeQueue:writeQueue logger:logger];
}

+ (Class)classForEncoding:(FBVideoStreamEncoding)encoding
{
  if ([encoding isEqualToString:FBVideoStreamEncodingBGRA]) {
    return FBDeviceVideoStream_BGRA.class;
  }
  if ([encoding isEqualToString:FBVideoStreamEncodingH264]) {
    return FBDeviceVideoStream_H264.class;
  }
  return nil;
}

+ (BOOL)configureVideoOutput:(AVCaptureVideoDataOutput *)output configuration:(FBVideoStreamConfiguration *)configuration error:(NSError **)error;
{
  output.alwaysDiscardsLateVideoFrames = YES;
  output.videoSettings = @{};
  return YES;
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

- (FBFuture<FBVideoStreamAttributes *> *)streamAttributes
{
  NSDictionary<NSString *, id> *dictionary = self.pixelBufferAttributes;
  if (!dictionary) {
    return [[FBDeviceControlError
      describe:@"Could not obtain stream attributes"]
      failFuture];
  }
  FBVideoStreamAttributes *attributes = [[FBVideoStreamAttributes alloc] initWithAttributes:dictionary];
  return [FBFuture futureWithResult:attributes];
}

- (FBFuture<NSNull *> *)startStreaming:(id<FBDataConsumer, FBDataConsumerStackConsuming>)consumer
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

@implementation FBDeviceVideoStream_BGRA

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

+ (BOOL)configureVideoOutput:(AVCaptureVideoDataOutput *)output configuration:(FBVideoStreamConfiguration *)configuration error:(NSError **)error;
{
  if (![super configureVideoOutput:output configuration:configuration error:error]) {
    return NO;
  }
  if (![output.availableVideoCVPixelFormatTypes containsObject:@(kCVPixelFormatType_32BGRA)]) {
    return [[FBDeviceControlError
      describe:@"kCVPixelFormatType_32BGRA is not a supported output type"]
      failBool:error];
  }
  output.videoSettings = @{
    (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
  };
  return YES;
}

@end

@implementation FBDeviceVideoStream_H264

- (void)consumeSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
  WriteFrameToAnnexBStream(sampleBuffer, self.consumer, self.logger, nil);
}

@end
