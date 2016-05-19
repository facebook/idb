/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDevice.h"

#import <IDEiOSSupportCore/DVTAbstractiOSDevice.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

@interface FBDevice ()
@property (nonatomic, strong) DVTAbstractiOSDevice *dvtDevice;
@property (nonatomic, strong) id<FBDeviceOperator> deviceOperator;
@end

@implementation FBDevice

+ (instancetype)deviceWithDeviceOperator:(id<FBDeviceOperator>)deviceOperator
{
  FBDevice *device = [self.class new];
  device.deviceOperator = deviceOperator;
  device.dvtDevice = deviceOperator.dvtDevice;
  return device;
}

- (NSString *)name
{
  return self.dvtDevice.name;
}

- (NSString *)modelName
{
  return self.dvtDevice.modelName;
}

- (NSString *)systemVersion
{
  return self.dvtDevice.softwareVersion;
}

- (NSString *)UDID
{
  return self.dvtDevice.identifier;
}

- (NSSet *)supportedArchitectures
{
  return self.dvtDevice.supportedArchitectures.set;
}

@end
