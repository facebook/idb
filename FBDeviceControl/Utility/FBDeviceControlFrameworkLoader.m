/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceControlFrameworkLoader.h"

#import <FBControlCore/FBControlCore.h>

#import <objc/runtime.h>

#import "FBDeviceControlError.h"
#import "FBAMDevice.h"
#import "FBAMDevice+Private.h"

@implementation FBDeviceControlFrameworkLoader

#pragma mark Initialziers

- (instancetype)init
{
  return [super initWithName:@"FBDeviceControl" frameworks:@[
    FBWeakFramework.MobileDevice,
    FBWeakFramework.DeviceLink,
  ]];
}

#pragma mark Public

- (BOOL)loadPrivateFrameworks:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error
{
  if (self.hasLoadedFrameworks) {
    return YES;
  }
  BOOL result = [super loadPrivateFrameworks:logger error:error];
  if (result) {
    [FBAMDevice defaultCalls];
  }
  if (logger.level >= FBControlCoreLogLevelDebug) {
    [FBAMDevice setDefaultLogLevel:9 logFilePath:@"/tmp/FBDeviceControl_MobileDevice.txt"];
  }
  return result;
}

@end
