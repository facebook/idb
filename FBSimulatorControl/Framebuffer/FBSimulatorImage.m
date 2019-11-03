/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

#import "FBFramebuffer.h"
#import "FBSimulatorError.h"
#import "FBSurfaceImageGenerator.h"

@interface FBSimulatorImage ()

@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) dispatch_queue_t writeQueue;
@property (nonatomic, strong, readonly) FBSurfaceImageGenerator *imageGenerator;
@property (nonatomic, strong, readonly) FBFramebuffer *framebuffer;
@property (nonatomic, strong, readwrite) NSUUID *consumerUUID;

@end

@implementation FBSimulatorImage

#pragma mark Initializers

+ (dispatch_queue_t)writeQueue
{
  return dispatch_queue_create("com.facebook.FBSimulatorControl.framebuffer.image", DISPATCH_QUEUE_SERIAL);
}

+ (instancetype)imageWithFramebuffer:(FBFramebuffer *)framebuffer logger:(id<FBControlCoreLogger>)logger
{
  return [[FBSimulatorImage alloc] initWithFramebuffer:framebuffer logger:logger];
}

- (instancetype)initWithFramebuffer:(FBFramebuffer *)framebuffer logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _framebuffer = framebuffer;
  _logger = logger;
  _consumerUUID = [NSUUID UUID];
  _writeQueue = FBSimulatorImage.writeQueue;
  _imageGenerator = [FBSurfaceImageGenerator imageGeneratorWithScale:NSDecimalNumber.one purpose:@"simulator_image" logger:self.logger];

  return self;
}

#pragma mark FBSimulatorImage

- (nullable CGImageRef)image
{
  if (![self.framebuffer isConsumerAttached:self.imageGenerator]) {
    [self.logger logFormat:@"Image Generator %@ not attached, attaching", self.imageGenerator];
    IOSurfaceRef surface = [self.framebuffer attachConsumer:self.imageGenerator onQueue:self.writeQueue];
    if (surface) {
      [self.logger logFormat:@"Surface %@ immediately available, adding to Image Generator %@", surface, self.imageGenerator];
      [self.imageGenerator didChangeIOSurface:surface];
    } else {
      [self.logger log:@"Surface for ImageGenerator not immedately available"];
    }
  }

  CGImageRef image = self.imageGenerator.image;
  if (image) {
    return image;
  }
  return self.imageGenerator.image;
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
