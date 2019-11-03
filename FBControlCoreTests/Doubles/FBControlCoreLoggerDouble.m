/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

- (id<FBControlCoreLogger>)withName:(NSString *)prefix
{
  return self;
}

- (id<FBControlCoreLogger>)withDateFormatEnabled:(BOOL)enabled
{
  return self;
}

- (NSString *)name
{
  return nil;
}

- (FBControlCoreLogLevel)level
{
  return FBControlCoreLogLevelMultiple;
}

@end
