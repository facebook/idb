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

#import <IDEiOSSupportCore/DVTAbstractiOSDevice.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

@implementation FBDevice

#pragma mark Initializers

- (instancetype)initWithDeviceOperator:(id<FBDeviceOperator>)operator dvtDevice:(DVTAbstractiOSDevice *)dvtDevice amDevce:(FBAMDevice *)amDevice
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _deviceOperator = operator;
  _dvtDevice = dvtDevice;
  _amDevice = amDevice;

  return self;
}

#pragma mark FBiOSTarget

- (NSString *)udid
{
  return self.dvtDevice.identifier;
}

#pragma mark Properties

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
    self.modelName,
    self.systemVersion,
    self.udid
  ];
}

@end
