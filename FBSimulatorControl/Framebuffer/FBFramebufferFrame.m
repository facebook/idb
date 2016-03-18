/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFramebufferFrame.h"

@implementation FBFramebufferFrame

- (instancetype)initWithTime:(CMTime)time timebase:(CMTimebaseRef)timebase image:(CGImageRef)image count:(NSUInteger)count size:(CGSize)size
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _time = time;
  _timebase = (CMTimebaseRef) CFRetain(timebase);
  _image = CGImageRetain(image);
  _count = count;
  _size = size;

  return self;
}

- (void)dealloc
{
  CGImageRelease(_image);
  CFRelease(_timebase);
}

- (instancetype)convertToTimebase:(CMTimebaseRef)destinationTimebase timescale:(CMTimeScale)timescale roundingMethod:(CMTimeRoundingMethod)roundingMethod
{
  CMTime destinationTime = CMSyncConvertTime(self.time, self.timebase, destinationTimebase);
  destinationTime = CMTimeConvertScale(destinationTime, timescale, roundingMethod);
  return [[FBFramebufferFrame alloc] initWithTime:destinationTime timebase:destinationTimebase image:self.image count:self.count size:self.size];
}

- (instancetype)updateWithCurrentTimeInTimebase:(CMTimebaseRef)timebase timescale:(CMTimeScale)timescale roundingMethod:(CMTimeRoundingMethod)roundingMethod
{
  CMTime time = CMTimebaseGetTimeWithTimeScale(timebase, timescale, roundingMethod);
  return [[FBFramebufferFrame alloc] initWithTime:time timebase:timebase image:self.image count:self.count size:self.size];
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Time %f | Count %lu", CMTimeGetSeconds(self.time), self.count];
}

@end
