/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBFutureTestHelpers.h"

@implementation FBFutureTestHelpers

+ (FBFuture<NSArray *> *)combineFutures:(NSArray *)futures
{
  return [FBFuture futureWithFutures:futures];
}

+ (FBFuture *)applyTimeout:(NSTimeInterval)timeout description:(NSString *)description toFuture:(FBFuture *)future
{
  return [future timeout:timeout waitingFor:@"%@", description];
}

@end
