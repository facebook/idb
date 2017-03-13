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
#import "FBFramebufferSurface.h"
#import "FBSimulatorError.h"
#import "FBSurfaceImageGenerator.h"
#import "FBSimulatorDiagnostics.h"
#import "FBFramebufferFrameGenerator.h"

@interface FBFramebufferImage ()

@property (nonatomic, copy, readonly) NSString *filePath;
@property (nonatomic, strong, readonly) id<FBSimulatorEventSink> eventSink;

@end

@interface FBFramebufferImage_FrameSink : FBFramebufferImage <FBFramebufferFrameSink>

@property (nonatomic, strong, readonly) dispatch_queue_t writeQueue;
@property (nonatomic, strong, readonly) FBFramebufferFrameGenerator *frameGenerator;

@property (nonatomic, strong, readwrite) FBFramebufferFrame *lastFrame;

- (instancetype)initWithFilePath:(NSString *)filePath frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator eventSink:(id<FBSimulatorEventSink>)eventSink writeQueue:(dispatch_queue_t)writeQueue;

@end

@interface FBFramebufferImage_Surface : FBFramebufferImage <FBFramebufferSurfaceConsumer>

@property (nonatomic, strong, readonly) FBSurfaceImageGenerator *imageGenerator;
@property (nonatomic, strong, readonly) FBFramebufferSurface *surface;
@property (nonatomic, strong, readwrite) NSUUID *consumerUUID;

- (instancetype)initWithFilePath:(NSString *)filePath eventSink:(id<FBSimulatorEventSink>)eventSink surface:(FBFramebufferSurface *)surface;

@end

@implementation FBFramebufferImage

#pragma mark Initializers

+ (instancetype)imageWithFilePath:(NSString *)filePath frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator eventSink:(id<FBSimulatorEventSink>)eventSink
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.FBSimulatorControl.framebuffer.image", DISPATCH_QUEUE_SERIAL);
  return [[FBFramebufferImage_FrameSink alloc] initWithFilePath:filePath frameGenerator:frameGenerator eventSink:eventSink writeQueue:queue];
}

+ (instancetype)imageWithFilePath:(NSString *)filePath surface:(FBFramebufferSurface *)surface eventSink:(id<FBSimulatorEventSink>)eventSink
{
  return [[FBFramebufferImage_Surface alloc] initWithFilePath:filePath eventSink:eventSink surface:surface];
}


- (instancetype)initWithFilePath:(NSString *)filePath eventSink:(id<FBSimulatorEventSink>)eventSink
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _filePath = filePath;
  _eventSink = eventSink;

  return self;
}

#pragma mark FBFramebufferImage

- (nullable CGImageRef)image
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return 0;
}

- (nullable NSData *)jpegImageDataWithError:(NSError **)error
{
  return [FBFramebufferImage jpegImageDataFromImage:self.image error:error];
}

- (nullable NSData *)pngImageDataWithError:(NSError **)error
{
  return [FBFramebufferImage pngImageDataFromImage:self.image error:error];
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

@end

@implementation FBFramebufferImage_FrameSink

- (instancetype)initWithFilePath:(NSString *)filePath frameGenerator:(FBFramebufferFrameGenerator *)frameGenerator eventSink:(id<FBSimulatorEventSink>)eventSink writeQueue:(dispatch_queue_t)writeQueue
{
  self = [super initWithFilePath:filePath eventSink:eventSink];
  if (!self) {
    return nil;
  }

  _frameGenerator = frameGenerator;
  _writeQueue = writeQueue;
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
  dispatch_group_async(teardownGroup, self.writeQueue, ^{
    FBDiagnostic *diagnostic = [[[[FBDiagnosticBuilder builder]
      updatePath:self.filePath]
      updateShortName:FBDiagnosticNameScreenshot]
      build];
    diagnostic = [FBFramebufferImage_FrameSink appendImage:self.lastFrame.image toDiagnostic:diagnostic];
    id<FBSimulatorEventSink> eventSink = self.eventSink;
    dispatch_async(dispatch_get_main_queue(), ^{
      [eventSink diagnosticAvailable:diagnostic];
    });
  });
}

@end

@implementation FBFramebufferImage_Surface

- (instancetype)initWithFilePath:(NSString *)filePath eventSink:(id<FBSimulatorEventSink>)eventSink surface:(FBFramebufferSurface *)surface
{
  self = [super initWithFilePath:filePath eventSink:eventSink];
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

#pragma mark FBFramebufferImage Implementation

- (nullable CGImageRef)image
{
  CGImageRef image = self.imageGenerator.image;
  if (image) {
    return image;
  }
  [self.surface attachConsumer:self];
  return self.imageGenerator.image;
}

@end
