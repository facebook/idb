/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBIDBError.h"

NSString *const FBIDBErrorDomain = @"com.facebook.idb";

@implementation FBIDBError

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  [self inDomain:FBIDBErrorDomain];

  return self;
}

@end
