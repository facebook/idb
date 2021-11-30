/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBCodeCoverageRequest.h"

@implementation FBCodeCoverageRequest

- (instancetype)initWithCollect:(BOOL)collect format:(FBCodeCoverageFormat)format
{
  self = [super init];
  if (!self) {
    return nil;
  }
  
  _collect = collect;
  _format = format;

  return self;
}

@end
