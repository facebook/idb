/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFramebufferImage.h"

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
#import "FBSimulatorEventSink.h"
#import "FBFramebufferRenderable.h"
#import "FBSimulatorError.h"
#import "FBSurfaceImageGenerator.h"

@interface FBFramebufferImage_FrameSink ()

@property (nonatomic, strong, readonly) dispatch_queue_t writeQueue;
@property (nonatomic, strong, readwrite) FBFramebufferFrame *lastFrame;

@property (nonatomic, strong, readonly) FBDiagnostic *diagnostic;
@property (nonatomic, strong, readonly) id<FBSimulatorEventSink> eventSink;

@end

@implementation FBFramebufferImage_FrameSink

+ (instancetype)imageWithDiagnostic:(FBDiagnostic *)diagnostic eventSink:(id<FBSimulatorEventSink>)eventSink
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.FBSimulatorControl.framebuffer.image", DISPATCH_QUEUE_SERIAL);
  return [[self alloc] initWithDiagnostic:diagnostic eventSink:eventSink writeQueue:queue];
}

- (instancetype)initWithDiagnostic:(FBDiagnostic *)diagnostic eventSink:(id<FBSimulatorEventSink>)eventSink writeQueue:(dispatch_queue_t)writeQueue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _diagnostic = [diagnostic copy];
  _eventSink = eventSink;
  _writeQueue = writeQueue;

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

- (nullable NSData *)jpegImageDataWithError:(NSError **)error
{
  return [FBFramebufferImage_FrameSink jpegImageDataFromImage:self.image error:error];
}

- (nullable NSData *)pngImageDataWithError:(NSError **)error
{
  return [FBFramebufferImage_FrameSink pngImageDataFromImage:self.image error:error];
}

#pragma mark Private

+ (FBDiagnostic *)appendImage:(CGImageRef)image toDiagnostic:(FBDiagnostic *)diagnostic
{
  FBDiagnosticBuilder *builder = [FBDiagnosticBuilder builderWithDiagnostic:diagnostic];
  NSString *filePath = [builder createPath];
  NSURL *url = [NSURL fileURLWithPath:filePath];
  CGImageDestinationRef destination = CGImageDestinationCreateWithURL(
    (__bridge CFURLRef) url,
    kUTTypePNG,
    1,
    NULL
  );
  if (!url) {
    CFRelease(destination);
    return diagnostic;
  }
  CGImageDestinationAddImage(destination, image, NULL);
  if (!CGImageDestinationFinalize(destination)) {
    CFRelease(destination);
    return diagnostic;
  }
  CFRelease(destination);

  return [[builder updatePath:filePath] build];
}

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

#pragma mark FBFramebufferCounterDelegate Implementation

- (void)frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator didUpdate:(FBFramebufferFrame *)frame
{
  dispatch_async(self.writeQueue, ^{
    self.lastFrame = frame;
  });
}

- (void)frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator didBecomeInvalidWithError:(NSError *)error teardownGroup:(dispatch_group_t)teardownGroup
{
  dispatch_group_async(teardownGroup, self.writeQueue, ^{
    FBDiagnostic *diagnostic = [FBFramebufferImage_FrameSink appendImage:self.lastFrame.image toDiagnostic:self.diagnostic];
    id<FBSimulatorEventSink> eventSink = self.eventSink;
    dispatch_async(dispatch_get_main_queue(), ^{
      [eventSink diagnosticAvailable:diagnostic];
    });
  });
}

@end

@interface FBFramebufferImage_Surface () <FBFramebufferRenderableConsumer>

@property (nonatomic, strong, readonly) FBDiagnostic *diagnostic;
@property (nonatomic, strong, readonly) id<FBSimulatorEventSink> eventSink;
@property (nonatomic, strong, readonly) FBSurfaceImageGenerator *imageGenerator;
@property (nonatomic, strong, readonly) FBFramebufferRenderable *renderable;

@property (nonatomic, strong, readwrite) NSUUID *consumerUUID;

@end

@implementation FBFramebufferImage_Surface

+ (instancetype)imageWithDiagnostic:(FBDiagnostic *)diagnostic renderable:(FBFramebufferRenderable *)renderable eventSink:(id<FBSimulatorEventSink>)eventSink
{
  return [[self alloc] initWithDiagnostic:diagnostic eventSink:eventSink renderable:renderable];
}

- (instancetype)initWithDiagnostic:(FBDiagnostic *)diagnostic eventSink:(id<FBSimulatorEventSink>)eventSink renderable:(FBFramebufferRenderable *)renderable
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _diagnostic = diagnostic;
  _eventSink = eventSink;
  _renderable = renderable;
  _consumerUUID = [NSUUID UUID];
  _imageGenerator = [FBSurfaceImageGenerator imageGeneratorWithScale:NSDecimalNumber.one logger:nil];

  return self;
}

#pragma mark FBFramebufferRenderableConsumer

- (NSString *)consumerIdentifier
{
  return NSStringFromClass(self.class);
}

- (void)didChangeIOSurface:(IOSurfaceRef)surface
{
  [self.imageGenerator didChangeIOSurface:surface];
}

- (void)didRecieveDamageRect:(CGRect)rect
{
  [self.imageGenerator didRecieveDamageRect:rect];
}

#pragma mark FBFramebufferImage Implementation

- (nullable CGImageRef)image
{
  CGImageRef image = self.imageGenerator.image;
  if (image) {
    return image;
  }
  [self.renderable attachConsumer:self];
  return self.imageGenerator.image;
}

- (nullable NSData *)jpegImageDataWithError:(NSError **)error
{
  return [FBFramebufferImage_FrameSink jpegImageDataFromImage:self.image error:error];
}

- (nullable NSData *)pngImageDataWithError:(NSError **)error
{
  return [FBFramebufferImage_FrameSink pngImageDataFromImage:self.image error:error];
}

@end
