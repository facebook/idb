/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
