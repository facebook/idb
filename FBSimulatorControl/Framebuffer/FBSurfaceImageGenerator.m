/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSurfaceImageGenerator.h"

#import <IOSurface/IOSurface.h>

#import <CoreMedia/CoreMedia.h>
#import <CoreImage/CoreImage.h>

#import <FBControlCore/FBControlCore.h>

@interface FBSurfaceImageGenerator ()

@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) CIFilter *scaleFilter;

@property (nonatomic, assign, readwrite) IOSurfaceRef surface;
@property (nonatomic, assign, readwrite) uint32_t lastSeedValue;

@end

@implementation FBSurfaceImageGenerator

+ (instancetype)imageGeneratorWithScale:(NSDecimalNumber *)scale logger:(id<FBControlCoreLogger>)logger
{
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

- (void)currentSurfaceChanged:(IOSurfaceRef)surface
{
  self.lastSeedValue = 0;
  if (surface != NULL && self.surface == NULL) {
    [self.logger.info logFormat:@"Removing old surface %@", surface];
    IOSurfaceDecrementUseCount(self.surface);
    self.surface = nil;
  }
  if (surface != NULL) {
    IOSurfaceIncrementUseCount(surface);
    self.surface = surface;
    [self.logger.info logFormat:@"Recieved IOSurface from Framebuffer Service %@", surface];
  }
}

- (nullable CGImageRef)availableImage
{
  uint32_t currentSeed = IOSurfaceGetSeed(self.surface);
  if (currentSeed == self.lastSeedValue) {
    return NULL;
  }
  self.lastSeedValue = currentSeed;
  return [self image];
}

- (CGImageRef)image
{
  CIContext *context = [CIContext contextWithOptions:nil];
  CIImage *ciImage = [CIImage imageWithIOSurface:self.surface];
  if (self.scaleFilter) {
    [self.scaleFilter setValue:ciImage forKey:kCIInputImageKey];
    ciImage = [self.scaleFilter outputImage];
    [self.scaleFilter setValue:ciImage forKey:kCIInputImageKey];
  }

  CGImageRef cgImage = [context createCGImage:ciImage fromRect:ciImage.extent];
  return cgImage;
}

@end
