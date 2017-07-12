/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorApplicationOperation.h"

@implementation FBSimulatorApplicationOperation

+ (instancetype)operationWithConfiguration:(FBApplicationLaunchConfiguration *)configuration process:(FBProcessInfo *)process
{
  return [[self alloc] initWithConfiguration:configuration process:process];
}

- (instancetype)initWithConfiguration:(FBApplicationLaunchConfiguration *)configuration process:(FBProcessInfo *)process
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _process = process;

  return self;
}

@end
