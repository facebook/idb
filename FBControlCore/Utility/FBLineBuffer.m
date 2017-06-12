/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBLineBuffer.h"

@interface FBLineBuffer ()

@property (nonatomic, strong, readwrite) NSMutableData *buffer;
@property (nonatomic, strong, readonly) NSData *terminalData;

@end

@implementation FBLineBuffer

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _buffer = [NSMutableData data];
  _terminalData = [NSData dataWithBytes:"\n" length:1];

  return self;
}

- (void)appendData:(NSData *)data
{
  [self.buffer appendData:data];
}

- (nullable NSData *)consumeCurrentData
{
  NSData *data = [self.buffer copy];
  self.buffer.data = NSData.data;
  return data;
}

- (nullable NSData *)consumeLineData
{
  if (self.buffer.length == 0) {
    return nil;
  }
  NSRange newlineRange = [self.buffer rangeOfData:self.terminalData options:0 range:NSMakeRange(0, self.buffer.length)];
  if (newlineRange.location == NSNotFound) {
    return nil;
  }
  NSData *lineData = [self.buffer subdataWithRange:NSMakeRange(0, newlineRange.location)];
  [self.buffer replaceBytesInRange:NSMakeRange(0, newlineRange.location + 1) withBytes:"" length:0];
  return lineData;
}

- (nullable NSString *)consumeLineString
{
  NSData *lineData = self.consumeLineData;
  if (!lineData) {
    return nil;
  }
  return [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
}

@end
