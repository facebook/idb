/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "CoreSimulatorDoubles.h"

#import <FBSimulatorControl/FBSimulatorControl.h>

@implementation FBSimulatorControlTests_SimDeviceType_Double
@end

@implementation FBSimulatorControlTests_SimDeviceRuntime_Double
@end

@implementation FBSimulatorControlTests_SimDevice_Double

@synthesize dataPath = _dataPath;

- (BOOL)isEqual:(FBSimulatorControlTests_SimDevice_Double *)object
{
  return [self.UDID isEqual:object.UDID];
}

- (NSString *)dataPath
{
  if (!_dataPath) {
    _dataPath = [[NSTemporaryDirectory()
      stringByAppendingPathComponent:@"SimDevice_Double"]
      stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_Data", self.UDID.UUIDString]];
    [NSFileManager.defaultManager createDirectoryAtPath:_dataPath withIntermediateDirectories:YES attributes:nil error:nil];
  }
  return _dataPath;
}

- (FBiOSTargetStateString)stateString
{
  return FBiOSTargetStateStringFromState(self.state);
}

@end

@implementation FBSimulatorControlTests_SimDeviceSet_Double
@end
