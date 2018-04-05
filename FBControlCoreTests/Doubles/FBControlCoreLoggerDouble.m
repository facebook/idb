/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBControlCoreLoggerDouble.h"

@implementation FBControlCoreLoggerDouble

- (id<FBControlCoreLogger>)log:(NSString *)string
{
  return self;
}

- (id<FBControlCoreLogger>)logFormat:(NSString *)format, ...
{
  return self;
}

- (id<FBControlCoreLogger>)info
{
  return self;
}

- (id<FBControlCoreLogger>)debug
{
  return self;
}

- (id<FBControlCoreLogger>)error
{
  return self;
}

- (id<FBControlCoreLogger>)onQueue:(dispatch_queue_t)queue
{
  return self;
}

- (id<FBControlCoreLogger>)withPrefix:(NSString *)prefix
{
  return self;
}

- (id<FBControlCoreLogger>)withDateFormatEnabled:(BOOL)enabled
{
  return self;
}

- (NSString *)prefix
{
  return nil;
}

- (FBControlCoreLogLevel)level
{
  return FBControlCoreLogLevelUnknown;
}

@end
