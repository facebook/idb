/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestProcessExecutor.h"

@implementation FBXCTestProcessInfo

- (instancetype)initWithProcessIdentifier:(pid_t)processIdentifier exitCode:(int)exitCode
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _processIdentifier = processIdentifier;
  _exitCode = exitCode;

  return self;
}

@end
