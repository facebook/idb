/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFramebufferCounter.h"

#import "FBSimulatorLogger.h"

@interface FBFramebufferCounter ()

@property (nonatomic, strong, readonly) id<FBSimulatorLogger> logger;
@property (nonatomic, assign, readonly) NSUInteger logFrequency;

@property (atomic, assign, readwrite) NSUInteger frameCount;

@end

@implementation FBFramebufferCounter

+ (instancetype)withLogFrequency:(NSUInteger)logFrequency logger:(id<FBSimulatorLogger>)logger
{
  return [[self alloc] initWithLogFrequency:logFrequency logger:logger];
}

- (instancetype)initWithLogFrequency:(NSUInteger)logFrequency logger:(id<FBSimulatorLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _logFrequency = logFrequency;
  _logger = logger;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"%lu", (unsigned long)self.frameCount];
}

#pragma mark FBFramebufferCounterDelegate Implementation

- (void)framebuffer:(FBSimulatorFramebuffer *)framebuffer didGetSize:(CGSize)size
{

}

- (void)framebufferDidUpdate:(FBSimulatorFramebuffer *)framebuffer withImage:(CGImageRef)image size:(CGSize)size
{
  self.frameCount++;
  if (self.frameCount % self.logFrequency != 0) {
    return;
  }

  dispatch_async(dispatch_get_main_queue(), ^{
    [self.logger.info logFormat:@"Frame Count %lu", self.frameCount];
  });
}

- (void)framebufferDidBecomeInvalid:(FBSimulatorFramebuffer *)framebuffer error:(NSError *)error
{

}

@end
