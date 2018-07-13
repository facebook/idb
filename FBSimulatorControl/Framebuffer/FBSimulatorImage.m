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

#import "FBFramebufferSurface.h"
#import "FBSimulatorError.h"
#import "FBSurfaceImageGenerator.h"

@interface FBSimulatorImage () <FBFramebufferSurfaceConsumer>

@property (nonatomic, strong, readonly) dispatch_queue_t writeQueue;
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

+ (instancetype)imageWithSurface:(FBFramebufferSurface *)surface
{
  return [[FBSimulatorImage alloc] initWithSurface:surface];
}

- (instancetype)initWithSurface:(FBFramebufferSurface *)surface
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _writeQueue = FBSimulatorImage.writeQueue;
  _surface = surface;
  _consumerUUID = [NSUUID UUID];
  _imageGenerator = [FBSurfaceImageGenerator imageGeneratorWithScale:NSDecimalNumber.one logger:nil];

  return self;
}

#pragma mark FBSimulatorImage

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

@end
