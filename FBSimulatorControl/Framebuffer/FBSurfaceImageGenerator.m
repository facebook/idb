/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSurfaceImageGenerator.h"

#import <IOSurface/IOSurface.h>

#import <CoreMedia/CoreMedia.h>
#import <CoreImage/CoreImage.h>

#import <FBControlCore/FBControlCore.h>

#import <IOSurface/IOSurface.h>

@interface FBSurfaceImageGenerator ()

@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) CIFilter *scaleFilter;

@property (nonatomic, strong, readwrite) IOSurface *surface;
@property (nonatomic, assign, readwrite) uint32_t lastSeedValue;

@end

@implementation FBSurfaceImageGenerator

+ (instancetype)imageGeneratorWithScale:(NSDecimalNumber *)scale purpose:(NSString *)purpose logger:(id<FBControlCoreLogger>)logger
{
  logger = [logger withName:[NSString stringWithFormat:@"%@_%@", logger.name, purpose]];
  return [[FBSurfaceImageGenerator alloc] initWithScale:scale logger:logger];
}

- (instancetype)initWithScale:(NSDecimalNumber *)scale logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _logger = logger;
  _lastSeedValue = 0;

  if ([scale isNotEqualTo:NSDecimalNumber.one]) {
    _scaleFilter = [CIFilter filterWithName:@"CILanczosScaleTransform"];
    [_scaleFilter setValue:scale forKey:@"inputScale"];
    [_scaleFilter setValue:NSDecimalNumber.one forKey:@"inputAspectRatio"];
  }

  return self;
}

#pragma mark Public

- (nullable CGImageRef)availableImage
{
  uint32_t currentSeed = [self.surface seed];
  if (currentSeed == self.lastSeedValue) {
    return NULL;
  }
  self.lastSeedValue = currentSeed;
  return [self image];
}

- (CGImageRef)image
{
  CIContext *context = [CIContext contextWithOptions:nil];
  CIImage *ciImage = [CIImage imageWithIOSurface:(__bridge IOSurfaceRef _Nonnull)(self.surface)];
  if (self.scaleFilter) {
    [self.scaleFilter setValue:ciImage forKey:kCIInputImageKey];
    ciImage = [self.scaleFilter outputImage];
    [self.scaleFilter setValue:ciImage forKey:kCIInputImageKey];
  }

  CGImageRef cgImage = [context createCGImage:ciImage fromRect:ciImage.extent];
  if (!cgImage) {
    return NULL;
  }
  CFAutorelease(cgImage);
  return cgImage;
}

#pragma mark FBFramebufferConsumer

- (void)didChangeIOSurface:(IOSurface *)surface
{
  self.lastSeedValue = 0;
  if (self.surface != NULL) {
    [self.logger.info logFormat:@"Removing old surface %@", surface];
    [surface decrementUseCount];
    self.surface = nil;
  }
  if (surface != NULL) {
    [surface incrementUseCount];
    [self.logger.info logFormat:@"Received IOSurface from Framebuffer Service %@", surface];
    self.surface = surface;
  }
}

- (void)didReceiveDamageRect:(CGRect)rect
{

}

@end
