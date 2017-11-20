/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorBitmapStream.h"

#import <FBControlCore/FBControlCore.h>
#import <IOSurface/IOSurface.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreVideo/CVPixelBufferIOSurface.h>

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

@interface FBSimulatorBitmapStream_Lazy : FBSimulatorBitmapStream

@end

@interface FBSimulatorBitmapStream_Eager : FBSimulatorBitmapStream

@property (nonatomic, assign, readonly) uint64_t timeInterval;
@property (nonatomic, strong, readwrite) FBDispatchSourceNotifier *timer;

- (instancetype)initWithSurface:(FBFramebufferSurface *)surface writeQueue:(dispatch_queue_t)writeQueue timeInterval:(uint64_t)timeInterval logger:(id<FBControlCoreLogger>)logger;

@end


@interface FBSimulatorBitmapStream ()

@property (nonatomic, weak, readonly) FBFramebufferSurface *surface;
@property (nonatomic, strong, readonly) dispatch_queue_t writeQueue;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *startFuture;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *stopFuture;

@property (nonatomic, strong, nullable, readwrite) id<FBFileConsumer> consumer;
@property (nonatomic, assign, nullable, readwrite) CVPixelBufferRef pixelBuffer;
@property (nonatomic, copy, nullable, readwrite) NSDictionary<NSString *, id> *pixelBufferAttributes;

- (void)pushFrame;

@end

@implementation FBSimulatorBitmapStream

+ (dispatch_queue_t)writeQueue
{
  return dispatch_queue_create("com.facebook.FBSimulatorControl.BitmapStream", DISPATCH_QUEUE_SERIAL);
}

+ (instancetype)lazyStreamWithSurface:(FBFramebufferSurface *)surface logger:(id<FBControlCoreLogger>)logger
{
  return [[FBSimulatorBitmapStream_Lazy alloc] initWithSurface:surface writeQueue:self.writeQueue logger:logger];
}

+ (instancetype)eagerStreamWithSurface:(FBFramebufferSurface *)surface framesPerSecond:(NSUInteger)framesPerSecond logger:(id<FBControlCoreLogger>)logger;
{
  uint64_t timeInterval = NSEC_PER_SEC / framesPerSecond;
  return [[FBSimulatorBitmapStream_Eager alloc] initWithSurface:surface writeQueue:self.writeQueue timeInterval:timeInterval logger:logger];
}

- (instancetype)initWithSurface:(FBFramebufferSurface *)surface writeQueue:(dispatch_queue_t)writeQueue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _surface = surface;
  _writeQueue = writeQueue;
  _logger = logger;
  _startFuture = FBMutableFuture.future;
  _stopFuture = FBMutableFuture.future;

  return self;
}

#pragma mark Public

- (nullable FBBitmapStreamAttributes *)streamAttributesWithError:(NSError **)error
{
  [self attachConsumerIfNeeded];
  NSDictionary<NSString *, id> *attributes = self.pixelBufferAttributes;
  if (!attributes) {
    return [[FBSimulatorError
      describe:@"Could not obtain stream attributes"]
      fail:error];
  }
  return [[FBBitmapStreamAttributes alloc] initWithAttributes:attributes];
}

- (FBFuture<NSNull *> *)startStreaming:(id<FBFileConsumer>)consumer
{
  if (self.consumer) {
    return [[FBSimulatorError
      describe:@"Cannot start streaming, a consumer is already attached"]
      failFuture];
  }
  self.consumer = consumer;
  [self attachConsumerIfNeeded];
  return self.startFuture;
}

- (FBFuture<NSNull *> *)stopStreaming
{
  if (!self.consumer) {
    return [[FBSimulatorError
      describe:@"Cannot stop streaming, no consumer attached"]
      failFuture];
  }
  if (![self.surface.attachedConsumers containsObject:self]) {
    return [[FBSimulatorError
      describe:@"Cannot stop streaming, is not attached to a surface"]
      failFuture];
  }
  [self.surface detachConsumer:self];
  [self.stopFuture resolveWithResult:NSNull.null];
  return self.stopFuture;
}

#pragma mark Private

- (void)attachConsumerIfNeeded
{
  if ([self.surface.attachedConsumers containsObject:self]) {
    return;
  }
  // If we have a surface now, we can start rendering, so mount the surface.
  IOSurfaceRef surface = [self.surface attachConsumer:self onQueue:self.writeQueue];
  if (surface) {
    dispatch_async(self.writeQueue, ^{
      [self didChangeIOSurface:surface];
    });
  }
}

#pragma mark FBFramebufferSurfaceConsumer

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

  // Signal that we've started
  [self.startFuture resolveWithResult:NSNull.null];

  return YES;
}

- (void)pushFrame
{
  if (!self.pixelBuffer || !self.consumer) {
    return;
  }
  [FBSimulatorBitmapStream writeBitmap:self.pixelBuffer consumer:self.consumer];
}

+ (void)writeBitmap:(CVPixelBufferRef)pixelBuffer consumer:(id<FBFileConsumer>)consumer
{
  CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

  void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
  size_t size = CVPixelBufferGetDataSize(pixelBuffer);
  NSData *data = [NSData dataWithBytesNoCopy:baseAddress length:size freeWhenDone:NO];
  [consumer consumeData:data];

  CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
}

#pragma mark FBiOSTargetContinuation

- (FBTerminationHandleType)handleType
{
  return FBTerminationHandleTypeVideoStreaming;
}

- (void)terminate
{
  [self.completed cancel];
}

- (FBFuture<NSNull *> *)completed
{
  return [self.stopFuture onQueue:self.writeQueue notifyOfCancellation:^(id _) {
    [self stopStreaming];
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

- (instancetype)initWithSurface:(FBFramebufferSurface *)surface writeQueue:(dispatch_queue_t)writeQueue timeInterval:(uint64_t)timeInterval logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithSurface:surface writeQueue:writeQueue logger:logger];
  if (!self) {
    return nil;
  }

  _timeInterval = timeInterval;

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
  self.timer = [FBDispatchSourceNotifier timerNotifierNotifierWithTimeInterval:self.timeInterval queue:self.writeQueue handler:^(FBDispatchSourceNotifier *_) {
    [self pushFrame];
  }];
  return YES;
}

@end
