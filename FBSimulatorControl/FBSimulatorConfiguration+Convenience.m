/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorConfiguration+Convenience.h"

#import "FBSimulatorConfiguration+DTMobile.h"
#import "SimRuntime.h"

@implementation FBSimulatorConfiguration (Convenience)

+ (instancetype)oldestAvailableOS
{
  return [self.orderedOSVersionRuntimes firstObject];
}

+ (instancetype)newestAvailableOS
{
  return [self.orderedOSVersionRuntimes lastObject];
}

#pragma mark Private

+ (NSArray *)orderedOSVersionRuntimes
{
  return [self.configurationsToAvailableRuntimes.allKeys sortedArrayUsingComparator:^NSComparisonResult(FBSimulatorConfiguration *left, FBSimulatorConfiguration *right) {
    return [left.osVersionString compare:right.osVersionString];
  }];
}

@end
