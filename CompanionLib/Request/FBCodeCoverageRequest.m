/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBCodeCoverageRequest.h"

@implementation FBCodeCoverageRequest

- (instancetype)initWithCollect:(BOOL)collect format:(FBCodeCoverageFormat)format enableContinuousCoverageCollection:(BOOL)enableContinuousCoverageCollection
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _collect = collect;
  _format = format;
  _shouldEnableContinuousCoverageCollection = enableContinuousCoverageCollection;
  return self;
}

@end
