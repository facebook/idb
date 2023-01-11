/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */



#import "FBExceptionInfo.h"

@implementation FBExceptionInfo

- (instancetype)initWithMessage:(NSString *)message file:(NSString *)file line:(NSUInteger)line
{
  self = [super init];

  if (!self) {
    return nil;
  }

  _message = message;
  _file = file;
  _line = line;

  return self;
}

- (instancetype)initWithMessage:(NSString *)message
{
  self = [super init];

  if (!self) {
    return nil;
  }

  _message = message;
  _file = nil;
  _line = 0;

  return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"Message %@ | File %@ | Line %lu", self.message, self.file, self.line];
}

@end
