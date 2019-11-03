/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorScreenshotCommands.h"

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorImage.h"

@interface FBSimulatorScreenshotCommands ()

@property (nonatomic, strong, readonly) FBSimulator *simulator;
@property (nonatomic, strong, nullable, readwrite) FBSimulatorImage *image;

@end

@implementation FBSimulatorScreenshotCommands

#pragma mark Initializers

+ (instancetype)commandsWithTarget:(id<FBiOSTarget>)target
{
  NSParameterAssert([target isKindOfClass:FBSimulator.class]);
  return [[self alloc] initWithSimulator:(FBSimulator *) target];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;

  return self;
}

#pragma mark FBScreenshotCommands

- (FBFuture<NSData *> *)takeScreenshot:(FBScreenshotFormat)format
{
  return [[self
    connectToImage]
    onQueue:self.simulator.workQueue fmap:^(FBSimulatorImage *image) {
      NSData *data = nil;
      NSError *error = nil;
      if ([format isEqualToString:FBScreenshotFormatJPEG]) {
        data = [image jpegImageDataWithError:&error];
      } else if ([format isEqualToString:FBScreenshotFormatPNG]) {
        data = [image pngImageDataWithError:&error];
      } else {
        return [[FBSimulatorError
          describeFormat:@"%@ is not a recognized screenshot format", format]
          failFuture];
      }
      return data ? [FBFuture futureWithResult:data] : [FBFuture futureWithError:error];
    }];
}

#pragma mark Private Methods

- (FBFuture<FBSimulatorImage *> *)connectToImage
{
  if (self.image) {
    return [FBFuture futureWithResult:self.image];
  }

  return [[self.simulator
    connectToFramebuffer]
    onQueue:self.simulator.workQueue fmap:^(FBFramebuffer *framebuffer) {
      FBSimulatorImage *image = [FBSimulatorImage imageWithFramebuffer:framebuffer logger:self.simulator.logger];
      self.image = image;
      return [FBFuture futureWithResult:image];
    }];
}

@end
