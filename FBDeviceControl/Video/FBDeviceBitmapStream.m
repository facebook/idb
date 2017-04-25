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
@property (nonatomic, strong, nullable, readwrite) id<FBFileConsumer> consumer;
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

- (void)dispatchPacket:(const void *)data length:(size_t)length
{
  static const size_t startCodeLength = 4;
  static const uint8_t startCode[] = {0x00, 0x00, 0x00, 0x01};
  [self.consumer consumeData:[NSData dataWithBytesNoCopy:(void *)startCode length:startCodeLength freeWhenDone:NO]];
  [self.consumer consumeData:[NSData dataWithBytesNoCopy:(void *)data length:length freeWhenDone:NO]];
}

- (void)consumeSampleBuffer:(CMSampleBufferRef)sampleBuffer
{
  BOOL syncFrame = NO;
  CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, 0);
  if (CFArrayGetCount(attachments) > 0) {
    CFBooleanRef notSyncFrame = NULL;
    Boolean keyExists = CFDictionaryGetValueIfPresent(CFArrayGetValueAtIndex(attachments, 0),
                                                      kCMSampleAttachmentKey_NotSync,
                                                      (const void **)&notSyncFrame);
    syncFrame = !keyExists || !CFBooleanGetValue(notSyncFrame);
  }

  CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);

  if (!self.pixelBufferAttributes) {
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format);
    NSDictionary *attributes = @{
                                 @"width" : @(dimensions.width),
                                 @"height" : @(dimensions.height),
                                 @"format" : @"h264",
                                 };
    self.pixelBufferAttributes = attributes;
    [self.logger logFormat:@"Mounting Surface with Attributes: %@", attributes];
  }

  if (syncFrame || !self.sentH264SPSPPS) {
    size_t numberOfParameterSets = 0;
    CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format,
                                                       0, NULL, NULL,
                                                       &numberOfParameterSets,
                                                       NULL);

    for (size_t i = 0; i < numberOfParameterSets; i++) {
      const uint8_t *data = NULL;
      size_t length = 0;
      CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format,
                                                         i,
                                                         &data,
                                                         &length,
                                                         NULL, NULL);

      [self dispatchPacket:data length:length];
    }

    self.sentH264SPSPPS = YES;
  }

  size_t bufferLength = 0;
  uint8_t *buffer = NULL;
  CMBlockBufferGetDataPointer(CMSampleBufferGetDataBuffer(sampleBuffer),
                              0,
                              NULL,
                              &bufferLength,
                              (char **)&buffer);

  size_t currentBufferOffset = 0;
  static const int headerLength = 4;
  while (currentBufferOffset < (bufferLength - headerLength)) {
    uint32_t thisUnitLength = 0;
    memcpy(&thisUnitLength, buffer + currentBufferOffset, headerLength);
    thisUnitLength = CFSwapInt32BigToHost(thisUnitLength);

    [self dispatchPacket:(buffer + currentBufferOffset + headerLength) length:thisUnitLength];

    currentBufferOffset += headerLength + thisUnitLength;
  }
}

@end
