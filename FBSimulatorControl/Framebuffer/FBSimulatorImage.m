/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorImage.h"

#import <CoreImage/CoreImage.h>

#import <FBControlCore/FBControlCore.h>

#import <objc/runtime.h>

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

#import "FBFramebufferFrame.h"
#import "FBFramebufferSurface.h"
#import "FBSimulatorError.h"
#import "FBSurfaceImageGenerator.h"
#import "FBFramebufferFrameGenerator.h"

@interface FBSimulatorImage ()

@property (nonatomic, strong, readonly) dispatch_queue_t writeQueue;

@end

@interface FBSimulatorImage_FrameSink : FBSimulatorImage <FBFramebufferFrameSink>

@property (nonatomic, strong, readonly) FBFramebufferFrameGenerator *frameGenerator;
@property (nonatomic, strong, readwrite) FBFramebufferFrame *lastFrame;

- (instancetype)initWithFrameGenerator:(FBFramebufferFrameGenerator *)frameGenerator;

@end

@interface FBSimulatorImage_Surface : FBSimulatorImage <FBFramebufferSurfaceConsumer>

@property (nonatomic, strong, readonly) FBSurfaceImageGenerator *imageGenerator;
@property (nonatomic, strong, readonly) FBFramebufferSurface *surface;
@property (nonatomic, strong, readwrite) NSUUID *consumerUUID;

- (instancetype)initWithSurface:(FBFramebufferSurface *)surface;

@end

@implementation FBSimulatorImage

#pragma mark Initializers

+ (dispatch_queue_t)writeQueue
{
  return dispatch_queue_create("com.facebook.FBSimulatorControl.framebuffer.image", DISPATCH_QUEUE_SERIAL);
}

+ (instancetype)imageWithFrameGenerator:(FBFramebufferFrameGenerator *)frameGenerator
{
  return [[FBSimulatorImage_FrameSink alloc] initWithFrameGenerator:frameGenerator];
}

+ (instancetype)imageWithSurface:(FBFramebufferSurface *)surface
{
  return [[FBSimulatorImage_Surface alloc] initWithSurface:surface];
}


- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _writeQueue = FBSimulatorImage.writeQueue;

  return self;
}

#pragma mark FBSimulatorImage

- (nullable CGImageRef)image
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return 0;
}

- (nullable NSData *)jpegImageDataWithError:(NSError **)error
{
  return [FBSimulatorImage jpegImageDataFromImage:self.image error:error];
}

- (nullable NSData *)pngImageDataWithError:(NSError **)error
{
  return [FBSimulatorImage pngImageDataFromImage:self.image error:error];
}

#pragma mark Private

+ (nullable NSData *)jpegImageDataFromImage:(nullable CGImageRef)image error:(NSError **)error
{
  return [self imageDataFromImage:image type:kUTTypeJPEG error:error];
}

+ (nullable NSData *)pngImageDataFromImage:(nullable CGImageRef)image error:(NSError **)error
{
  return [self imageDataFromImage:image type:kUTTypePNG error:error];
}

+ (nullable NSData *)imageDataFromImage:(nullable CGImageRef)image type:(CFStringRef)type error:(NSError **)error
{
  if (!image) {
    return [[FBSimulatorError
      describe:@"No Image available to encode"]
      fail:error];
  }

  NSMutableData *data = [NSMutableData data];
  CGImageDestinationRef destination = CGImageDestinationCreateWithData(
    (CFMutableDataRef) data,
    type,
    1,
    NULL
  );
  CGImageDestinationAddImage(destination, image, NULL);
  if (!CGImageDestinationFinalize(destination)) {
    CFRelease(destination);
    return [[FBSimulatorError
      describe:@"Could not finalize the creation of the Image"]
      fail:error];
  }
  CFRelease(destination);
  return data;
}

@end

@implementation FBSimulatorImage_FrameSink

- (instancetype)initWithFrameGenerator:(FBFramebufferFrameGenerator *)frameGenerator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _frameGenerator = frameGenerator;
  [frameGenerator attachSink:self];

  return self;
}

#pragma mark Public

- (nullable CGImageRef)image
{
  CGImageRef image = self.lastFrame.image;
  if (!image) {
    return NULL;
  }
  return image;
}

#pragma mark FBFramebufferCounterDelegate Implementation

- (void)frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator didUpdate:(FBFramebufferFrame *)frame
{
  dispatch_async(self.writeQueue, ^{
    self.lastFrame = frame;
  });
}

- (void)frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator didBecomeInvalidWithError:(NSError *)error teardownGroup:(dispatch_group_t)teardownGroup
{
}

@end

@implementation FBSimulatorImage_Surface

- (instancetype)initWithSurface:(FBFramebufferSurface *)surface
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _surface = surface;
  _consumerUUID = [NSUUID UUID];
  _imageGenerator = [FBSurfaceImageGenerator imageGeneratorWithScale:NSDecimalNumber.one logger:nil];

  return self;
}

#pragma mark FBFramebufferSurfaceConsumer

- (NSString *)consumerIdentifier
{
  return NSStringFromClass(self.class);
}

- (void)didChangeIOSurface:(IOSurfaceRef)surface
{
  [self.imageGenerator didChangeIOSurface:surface];
}

- (void)didReceiveDamageRect:(CGRect)rect
{
  [self.imageGenerator didReceiveDamageRect:rect];
}

#pragma mark FBSimulatorImage Implementation

- (nullable CGImageRef)image
{
  CGImageRef image = self.imageGenerator.image;
  if (image) {
    return image;
  }
  IOSurfaceRef surface = [self.surface attachConsumer:self onQueue:self.writeQueue];
  if (surface) {
    [self didChangeIOSurface:surface];
  }
  return self.imageGenerator.image;
}

@end
