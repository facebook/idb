/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDevice.h"
#import "FBDevice+Private.h"

#import <IDEiOSSupportCore/DVTiOSDevice.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBDeviceSet+Private.h"
#import "FBAMDevice.h"
#import "FBiOSDeviceOperator+Private.h"

@implementation FBDevice

@synthesize deviceOperator = _deviceOperator;
@synthesize dvtDevice = _dvtDevice;

#pragma mark Initializers

- (instancetype)initWithSet:(FBDeviceSet *)set amDevice:(FBAMDevice *)amDevice logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _set = set;
  _amDevice = amDevice;
  _logger = logger;

  return self;
}

#pragma mark FBiOSTarget

- (NSString *)udid
{
  return self.amDevice.udid;
}

- (NSString *)name
{
  return self.amDevice.deviceName;
}

- (id<FBControlCoreConfiguration_Device>)deviceConfiguration
{
  return self.amDevice.deviceConfiguration;
}

- (id<FBControlCoreConfiguration_OS>)osConfiguration
{
  return self.amDevice.osConfiguration;
}

#pragma mark Properties

- (DVTiOSDevice *)dvtDevice
{
  if (_dvtDevice == nil) {
    _dvtDevice = [self.set dvtDeviceWithUDID:self.udid];
  }
  return _dvtDevice;
}

- (id<FBDeviceOperator>)deviceOperator
{
  if (_deviceOperator == nil) {
    _deviceOperator = [[FBiOSDeviceOperator alloc] initWithiOSDevice:self.dvtDevice];
  }
  return _deviceOperator;
}

- (NSString *)modelName
{
  return self.amDevice.modelName;
}

- (NSString *)systemVersion
{
  return self.amDevice.systemVersion;
}

- (NSSet *)supportedArchitectures
{
  return self.dvtDevice.supportedArchitectures.set;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Device | %@ | %@ | %@ | %@",
    self.name,
    self.udid,
    self.osConfiguration,
    self.deviceConfiguration
  ];
}

@end
