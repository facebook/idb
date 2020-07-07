/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorBitmapStream.h"

#import <FBControlCore/FBControlCore.h>
#import <IOSurface/IOSurface.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreVideo/CVPixelBufferIOSurface.h>
#import <VideoToolbox/VideoToolbox.h>

#import <SimulatorKit/SimDeviceFramebufferService.h>
#import <SimulatorKit/SimDeviceIOPortInterface-Protocol.h>
#import <SimulatorKit/SimDisplayIOSurfaceRenderable-Protocol.h>
#import <SimulatorKit/SimDisplayRenderable-Protocol.h>
#import <SimulatorKit/SimDeviceIOPortInterface-Protocol.h>
#import <SimulatorKit/SimDisplayDescriptorState-Protocol.h>
#import <SimulatorKit/SimDeviceIOPortConsumer-Protocol.h>
#import <SimulatorKit/SimDeviceIOPortDescriptorState-Protocol.h>
#import <SimulatorKit/SimDeviceIOPortInterface-Protocol.h>
#import <SimulatorKit/SimDisplayIOSurfaceRenderable-Protocol.h>
#import <SimulatorKit/SimDisplayRenderable-Protocol.h>

#import "FBSimulatorError.h"

@interface FBSimulatorBitmapStream_Lazy : FBSimulatorBitmapStream

@end

@interface FBSimulatorBitmapStream_Eager : FBSimulatorBitmapStream

@property (nonatomic, assign, readonly) NSUInteger framesPerSecond;
@property (nonatomic, strong, readwrite) FBDispatchSourceNotifier *timer;

- (instancetype)initWithFramebuffer:(FBFramebuffer *)framebuffer encoding:(FBBitmapStreamEncoding)encoding writeQueue:(dispatch_queue_t)writeQueue framesPerSecond:(NSUInteger)framesPerSecond logger:(id<FBControlCoreLogger>)logger;

@end

@interface FBSimulatorBitmapStream ()

@property (nonatomic, weak, readonly) FBFramebuffer *framebuffer;
@property (nonatomic, copy, readonly) FBBitmapStreamEncoding encoding;
@property (nonatomic, strong, readonly) dispatch_queue_t writeQueue;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *startedFuture;
@property (nonatomic, strong, readwrite) FBMutableFuture<NSNull *> *stoppedFuture;


@property (nonatomic, assign, readwrite) NSUInteger frameNumber;
@property (nonatomic, strong, nullable, readwrite) id<FBDataConsumer> consumer;
@property (nonatomic, assign, nullable, readwrite) CVPixelBufferRef pixelBuffer;
@property (nonatomic, assign, readwrite) CFTimeInterval timeAtFirstFrame;
@property (nonatomic, assign, nullable, readwrite) VTCompressionSessionRef compressionSession;
@property (nonatomic, copy, nullable, readwrite) NSDictionary<NSString *, id> *pixelBufferAttributes;

- (void)pushFrame;

@end

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

static void EncodeCallbck(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus encodeStats, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer)
{
  FBSimulatorBitmapStream *stream = (__bridge FBSimulatorBitmapStream *)(outputCallbackRefCon);
  WriteFrameToAnnexBStream(sampleBuffer, stream.consumer, stream.logger, nil);
}

static NSDictionary<NSString *, id> *SourceImageBufferAttributes(CVPixelBufferRef pixelBuffer)
{
  return @{
    (NSString *) kCVPixelBufferWidthKey: @(CVPixelBufferGetWidth(pixelBuffer)),
    (NSString *) kCVPixelBufferHeightKey: @(CVPixelBufferGetHeight(pixelBuffer)),
  };
}

static NSDictionary<NSString *, id> * EncoderSpecification()
{
  return @{
    (NSString *) kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: @YES,
  };
}

@implementation FBSimulatorBitmapStream

+ (dispatch_queue_t)writeQueue
{
  return dispatch_queue_create("com.facebook.FBSimulatorControl.BitmapStream", DISPATCH_QUEUE_SERIAL);
}

+ (instancetype)lazyStreamWithFramebuffer:(FBFramebuffer *)framebuffer encoding:(FBBitmapStreamEncoding)encoding logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  return [[FBSimulatorBitmapStream_Lazy alloc] initWithFramebuffer:framebuffer encoding:encoding writeQueue:self.writeQueue logger:logger];
}

+ (instancetype)eagerStreamWithFramebuffer:(FBFramebuffer *)framebuffer encoding:(FBBitmapStreamEncoding)encoding framesPerSecond:(NSUInteger)framesPerSecond logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  return [[FBSimulatorBitmapStream_Eager alloc] initWithFramebuffer:framebuffer encoding:encoding writeQueue:self.writeQueue framesPerSecond:framesPerSecond logger:logger];
}

- (instancetype)initWithFramebuffer:(FBFramebuffer *)framebuffer encoding:(FBBitmapStreamEncoding)encoding writeQueue:(dispatch_queue_t)writeQueue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _framebuffer = framebuffer;
  _encoding = encoding;
  _writeQueue = writeQueue;
  _logger = logger;
  _startedFuture = FBMutableFuture.future;
  _stoppedFuture = FBMutableFuture.future;

  return self;
}

#pragma mark Public

- (FBFuture<FBBitmapStreamAttributes *> *)streamAttributes
{
  return [[self
    attachConsumerIfNeeded]
    onQueue:self.writeQueue fmap:^ FBFuture<FBBitmapStreamAttributes *> * (id _) {
      NSDictionary<NSString *, id> *dictionary = self.pixelBufferAttributes;
      if (!dictionary) {
        return [[FBSimulatorError
          describe:@"Could not obtain stream attributes"]
          failFuture];
      }
      FBBitmapStreamAttributes *attributes = [[FBBitmapStreamAttributes alloc] initWithAttributes:dictionary];
      return [FBFuture futureWithResult:attributes];
    }];
}

- (FBFuture<NSNull *> *)startStreaming:(id<FBDataConsumer>)consumer
{
  return [[FBFuture
    onQueue:self.writeQueue resolve:^ FBFuture<NSNull *> * {
      if (self.startedFuture.hasCompleted) {
        return [[FBSimulatorError
          describe:@"Cannot start streaming, since streaming is stopped"]
          failFuture];
      }
      if (self.consumer) {
        return [[FBSimulatorError
          describe:@"Cannot start streaming, since streaming has already has started"]
          failFuture];
      }
      self.consumer = consumer;
      return [self attachConsumerIfNeeded];
    }]
    onQueue:self.writeQueue fmap:^(id _) {
      return self.startedFuture;
    }];
}

- (FBFuture<NSNull *> *)stopStreaming
{
  return [FBFuture
    onQueue:self.writeQueue resolve:^ FBFuture<NSNull *> *{
      if (self.stoppedFuture.hasCompleted) {
        return self.stoppedFuture;
      }
      id<FBDataConsumer> consumer = self.consumer;
      if (!consumer) {
        return [[FBSimulatorError
          describe:@"Cannot stop streaming, no consumer attached"]
          failFuture];
      }
      if (![self.framebuffer.attachedConsumers containsObject:self]) {
        return [[FBSimulatorError
          describe:@"Cannot stop streaming, is not attached to a surface"]
          failFuture];
      }
      self.consumer = nil;
      [self.framebuffer detachConsumer:self];
      [consumer consumeEndOfFile];
      [self.stoppedFuture resolveWithResult:NSNull.null];
      return self.stoppedFuture;
    }];
}

#pragma mark Private

- (FBFuture<NSNull *> *)attachConsumerIfNeeded
{
  return [FBFuture
    onQueue:self.writeQueue resolve:^{
      if ([self.framebuffer isConsumerAttached:self]) {
        [self.logger logFormat:@"Already attached %@ as a consumer", self];
        return FBFuture.empty;
      }
      // If we have a surface now, we can start rendering, so mount the surface.
      IOSurfaceRef surface = [self.framebuffer attachConsumer:self onQueue:self.writeQueue];
      [self didChangeIOSurface:surface];
      return FBFuture.empty;
    }];
}

#pragma mark FBFramebufferConsumer

- (NSString *)consumerIdentifier
{
  return NSStringFromClass(self.class);
}

- (void)didChangeIOSurface:(nullable IOSurfaceRef)surface
{
  [self mountSurface:surface error:nil];
  [self pushFrame];
}

- (void)didReceiveDamageRect:(CGRect)rect
{
}

#pragma mark Private

- (BOOL)mountSurface:(IOSurfaceRef)surface error:(NSError **)error
{
  // Remove the old pixel buffer.
  CVPixelBufferRef oldBuffer = self.pixelBuffer;
  if (oldBuffer) {
    CVPixelBufferRelease(oldBuffer);
  }

  // Make a Buffer from the Surface
  CVPixelBufferRef buffer = NULL;
  CVReturn status = CVPixelBufferCreateWithIOSurface(
    NULL,
    surface,
    NULL,
    &buffer
  );
  if (status != kCVReturnSuccess) {
    return [[FBSimulatorError
      describeFormat:@"Failed to create Pixel Buffer from Surface with errorCode %d", status]
      failBool:error];
  }

  // Get the Attributes
  NSDictionary<NSString *, id> *attributes = FBBitmapStreamPixelBufferAttributesFromPixelBuffer(buffer);
  [self.logger logFormat:@"Mounting Surface with Attributes: %@", attributes];

  // Swap the pixel buffers.
  self.pixelBuffer = buffer;
  self.pixelBufferAttributes = attributes;

  if ([self.encoding isEqualToString:FBBitmapStreamEncodingH264]) {
    VTCompressionSessionRef compressionSession = NULL;
    status = VTCompressionSessionCreate(
      nil, // Allocator
      (int32_t) CVPixelBufferGetWidth(buffer),
      (int32_t) CVPixelBufferGetHeight(buffer),
      kCMVideoCodecType_H264,
      (__bridge CFDictionaryRef) EncoderSpecification(),
      (__bridge CFDictionaryRef) SourceImageBufferAttributes(buffer),
      nil, // Compressed Data Allocator
      EncodeCallbck,
      (__bridge void * _Nullable)(self), // Callback Ref.
      &compressionSession
    );
    if (status != noErr) {
      return [[FBSimulatorError
        describeFormat:@"Failed to start Compression Session %d", status]
        failBool:error];
    }
    status = VTSessionSetProperties(
      compressionSession,
      (__bridge CFDictionaryRef) self.compressionSessionProperties
    );
    if (status != noErr) {
      return [[FBSimulatorError
        describeFormat:@"Failed to set compression session properties %d", status]
        failBool:error];
    }
    status = VTCompressionSessionPrepareToEncodeFrames(compressionSession);
    if (status != noErr) {
      return [[FBSimulatorError
        describeFormat:@"Failed to prepare compression session %d", status]
        failBool:error];
    }
    self.compressionSession = compressionSession;
  }

  // Signal that we've started
  [self.startedFuture resolveWithResult:NSNull.null];

  return YES;
}

- (void)pushFrame
{
  CVPixelBufferRef pixelBufer = self.pixelBuffer;
  id<FBDataConsumer> consumer = self.consumer;
  if (!pixelBufer || !consumer) {
    return;
  }
  NSUInteger frameNumber = self.frameNumber;
  if (frameNumber == 0) {
    self.timeAtFirstFrame = CFAbsoluteTimeGetCurrent();
  }
  CFTimeInterval timeAtFirstFrame = self.timeAtFirstFrame;
  VTCompressionSessionRef compressionSession = self.compressionSession;
  if (compressionSession) {
    [FBSimulatorBitmapStream writeEncodedFrame:pixelBufer compressionSession:compressionSession frameNumber:frameNumber timeAtFirstFrame:timeAtFirstFrame];
  } else {
    [FBSimulatorBitmapStream writeBitmap:pixelBufer consumer:consumer];
  }
  self.frameNumber = frameNumber + 1;
}

+ (void)writeBitmap:(CVPixelBufferRef)pixelBuffer consumer:(id<FBDataConsumer>)consumer
{
  CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

  void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
  size_t size = CVPixelBufferGetDataSize(pixelBuffer);
  NSData *data = [NSData dataWithBytesNoCopy:baseAddress length:size freeWhenDone:NO];
  [consumer consumeData:data];

  CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
}

+ (void)writeEncodedFrame:(CVPixelBufferRef)pixelBuffer compressionSession:(VTCompressionSessionRef)compressionSession frameNumber:(NSUInteger)frameNumber timeAtFirstFrame:(CFTimeInterval)timeAtFirstFrame
{
  VTEncodeInfoFlags flags;
  CMTime time = CMTimeMakeWithSeconds(CFAbsoluteTimeGetCurrent() - timeAtFirstFrame, NSEC_PER_SEC);
  OSStatus status = VTCompressionSessionEncodeFrame(
    compressionSession,
    pixelBuffer,
    time,
    kCMTimeInvalid,  // Frame duration
    NULL,  // Frame properties
    NULL,  // Source Frame Reference for callback.
    &flags
  );
  (void) status;
}

- (NSDictionary<NSString *, id> *)compressionSessionProperties
{
  return @{
    (NSString *) kVTCompressionPropertyKey_RealTime: @YES,
    (NSString *) kVTCompressionPropertyKey_ProfileLevel: (NSString *) kVTProfileLevel_H264_High_AutoLevel,
    (NSString *) kVTCompressionPropertyKey_AllowFrameReordering: @NO,
  };
}

#pragma mark FBiOSTargetContinuation

- (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeVideoStreaming;
}

- (FBFuture<NSNull *> *)completed
{
  return [[FBMutableFuture.future
    resolveFromFuture:self.stoppedFuture]
    onQueue:self.writeQueue respondToCancellation:^{
      return [self stopStreaming];
    }];
}

@end

@implementation FBSimulatorBitmapStream_Lazy

- (void)didReceiveDamageRect:(CGRect)rect
{
  [self pushFrame];
}


@end

@implementation FBSimulatorBitmapStream_Eager

- (instancetype)initWithFramebuffer:(FBFramebuffer *)framebuffer encoding:(FBBitmapStreamEncoding)encoding writeQueue:(dispatch_queue_t)writeQueue framesPerSecond:(NSUInteger)framesPerSecond logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithFramebuffer:framebuffer encoding:encoding writeQueue:writeQueue logger:logger];
  if (!self) {
    return nil;
  }

  _framesPerSecond = framesPerSecond;

  return self;
}

#pragma mark Private

- (BOOL)mountSurface:(IOSurfaceRef)surface error:(NSError **)error
{
  if (![super mountSurface:surface error:error]) {
    return NO;
  }

  if (self.timer) {
    [self.timer terminate];
    self.timer = nil;
  }
  uint64_t timeInterval = NSEC_PER_SEC / self.framesPerSecond;
  self.timer = [FBDispatchSourceNotifier timerNotifierNotifierWithTimeInterval:timeInterval queue:self.writeQueue handler:^(FBDispatchSourceNotifier *_) {
    [self pushFrame];
  }];

  return YES;
}

- (NSDictionary<NSString *, id> *)compressionSessionProperties
{
  return @{
    (NSString *) kVTCompressionPropertyKey_RealTime: @YES,
    (NSString *) kVTCompressionPropertyKey_ProfileLevel: (NSString *) kVTProfileLevel_H264_High_AutoLevel,
    (NSString *) kVTCompressionPropertyKey_ExpectedFrameRate: @(self.framesPerSecond),
    (NSString *) kVTCompressionPropertyKey_MaxKeyFrameInterval: @2,
    (NSString *) kVTCompressionPropertyKey_AllowFrameReordering: @NO,
  };
}

@end
