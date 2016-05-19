/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDeviceControlError.h"

NSString *const FBDeviceControlErrorDomain = @"com.facebook.FBDeviceControl";

@implementation FBDeviceControlError

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  [self inDomain:FBDeviceControlErrorDomain];

  return self;
}

@end
