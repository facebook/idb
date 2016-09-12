/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorScale.h"

#pragma mark Scales

@implementation FBSimulatorScale_25

- (NSString *)scaleString
{
  return @"0.25";
}

@end

@implementation FBSimulatorScale_50

- (NSString *)scaleString
{
  return @"0.50";
}

@end

@implementation FBSimulatorScale_75

- (NSString *)scaleString
{
  return @"0.75";
}

@end

@implementation FBSimulatorScale_100

- (NSString *)scaleString
{
  return @"1.00";
}

@end
