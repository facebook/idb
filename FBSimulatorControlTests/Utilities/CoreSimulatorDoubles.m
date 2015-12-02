/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "CoreSimulatorDoubles.h"

@implementation FBSimulatorControlTests_SimDeviceType_Double
@end

@implementation FBSimulatorControlTests_SimDeviceRuntime_Double
@end

@implementation FBSimulatorControlTests_SimDevice_Double

- (BOOL)isEqual:(FBSimulatorControlTests_SimDevice_Double *)object
{
  return [self.UDID isEqual:object.UDID];
}

@end

@implementation FBSimulatorControlTests_SimDeviceSet_Double
@end
