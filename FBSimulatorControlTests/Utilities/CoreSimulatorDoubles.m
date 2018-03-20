/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "CoreSimulatorDoubles.h"

#import <FBSimulatorControl/FBSimulatorControl.h>

@implementation FBSimulatorControlTests_SimDeviceType_Double
@end

@implementation FBSimulatorControlTests_SimDeviceRuntime_Double
@end

@implementation FBSimulatorControlTests_SimDeviceNotificationManager_Double

- (BOOL)unregisterNotificationHandler:(unsigned long long)arg1 error:(id *)arg2 {
  return NO;
}

- (unsigned long long)registerNotificationHandler:(void (^)(NSDictionary *))arg2 {
  return 0;
}
- (unsigned long long)registerNotificationHandlerOnQueue:(NSObject<OS_dispatch_queue> *)arg1 handler:(void (^)(NSDictionary *))arg2 {
  return 0;
}
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

- (FBSimulatorStateString)stateString
{
  return FBSimulatorStateStringFromState(self.state);
}

@end

@implementation FBSimulatorControlTests_SimDeviceSet_Double
- (id)notificationManager
{
  return [[FBSimulatorControlTests_SimDeviceNotificationManager_Double alloc] init];
}
@end
