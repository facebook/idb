/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFramebufferFrameGenerator.h"

#import <CoreMedia/CoreMedia.h>

#import <FBControlCore/FBControlCore.h>

#import <SimulatorKit/SimDeviceFramebufferBackingStore.h>

#import "FBFramebufferFrame.h"
#import "FBFramebufferDelegate.h"

static const NSInteger FBFramebufferLogFrameFrequency = 100;
// Timescale is in nanonseconds
static const CMTimeScale FBSimulatorFramebufferTimescale = 10E8;
static const CMTimeRoundingMethod FBSimulatorFramebufferRoundingMethod = kCMTimeRoundingMethod_Default;

@interface FBFramebufferFrameGenerator ()

@property (nonatomic, weak, readonly) FBFramebuffer *framebuffer;
@property (nonatomic, weak, readonly) id<FBFramebufferDelegate> delegate;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@property (atomic, assign, readwrite) CMTimebaseRef timebase;
@property (atomic, assign, readwrite) NSUInteger frameCount;
@property (atomic, assign, readwrite) CGSize size;

@end

@implementation FBFramebufferFrameGenerator

#pragma mark Initializers

+ (instancetype)generatorWithFramebuffer:(FBFramebuffer *)framebuffer delegate:(id<FBFramebufferDelegate>)delegate logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithFramebuffer:framebuffer delegate:delegate logger:logger];
}

- (instancetype)initWithFramebuffer:(FBFramebuffer *)framebuffer delegate:(id<FBFramebufferDelegate>)delegate logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _framebuffer = framebuffer;
  _delegate = delegate;
  _logger = logger;

  _frameCount = 0;
  _size = CGSizeZero;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Size %@ | Frame Count %ld",
    NSStringFromSize(self.size),
    self.frameCount
  ];
}

#pragma mark FBJSONSerializable Implementation

- (id)jsonSerializableRepresentation
{
  return @{
    @"size" : NSStringFromSize(self.size)
  };
}

#pragma mark Public Methods

- (void)firstFrameWithBackingStore:(SimDeviceFramebufferBackingStore *)backingStore
{
  CMTimebaseRef timebase = NULL;
  CMTimebaseCreateWithMasterClock(
    kCFAllocatorDefault,
    CMClockGetHostTimeClock(),
    &timebase
  );
  NSAssert(timebase, @"Expected to be able to construct timebase");
  CMTimebaseSetRate(timebase, 1.0);
  self.timebase = timebase;

  [self pushNewFrameFromBackingStore:backingStore];

}

- (void)backingStoreDidUpdate:(SimDeviceFramebufferBackingStore *)backingStore
{
  [self pushNewFrameFromBackingStore:backingStore];
}

- (void)frameSteamEnded
{
  if (self.timebase) {
    CFRelease(self.timebase);
    self.timebase = nil;
  }
}

#pragma mark Private

- (void)pushNewFrameFromBackingStore:(SimDeviceFramebufferBackingStore *)backingStore
{
  CGSize size = NSMakeSize(backingStore.pixelsWide, backingStore.pixelsHigh);
  self.size = size;

  // Create and delegate the frame creation
  FBFramebufferFrame *frame = [self frameFromCurrentTime:backingStore.image size:size];
  [self.delegate framebuffer:self.framebuffer didUpdate:frame];

  // Log and increment.
  if (self.frameCount == 0) {
    [self.logger.info log:@"First Frame"];
  }
  else if (self.frameCount % FBFramebufferLogFrameFrequency == 0) {
    [self.logger.info logFormat:@"Frame Count %lu", self.frameCount];
  }
  self.frameCount = self.frameCount + 1;
}

- (FBFramebufferFrame *)frameFromCurrentTime:(CGImageRef)image size:(CGSize)size
{
  CMTime time = CMTimebaseGetTimeWithTimeScale(self.timebase, FBSimulatorFramebufferTimescale, FBSimulatorFramebufferRoundingMethod);
  return [[FBFramebufferFrame alloc] initWithTime:time timebase:self.timebase image:image count:self.frameCount size:size];
}

@end
