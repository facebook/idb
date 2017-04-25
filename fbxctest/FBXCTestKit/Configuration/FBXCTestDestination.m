/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestDestination.h"

#import <FBSimulatorControl/FBSimulatorControl.h>

@implementation FBXCTestDestination

- (NSString *)xctestPath
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

@end

@implementation FBXCTestDestinationMacOSX

- (NSString *)xctestPath
{
  return [FBControlCoreGlobalConfiguration.developerDirectory
    stringByAppendingPathComponent:@"usr/bin/xctest"];
}

@end

@implementation FBXCTestDestinationiPhoneSimulator

- (instancetype)initWithModel:(nullable FBDeviceModel)model version:(nullable FBOSVersionName)version
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _model = model;
  _version = version;

  return self;
}

- (FBSimulatorConfiguration *)simulatorConfiguration
{
  FBSimulatorConfiguration *configuration = [FBSimulatorConfiguration defaultConfiguration];
  if (self.model) {
    configuration = [configuration withDeviceModel:self.model];
  }
  if (self.version) {
    configuration = [configuration withOSNamed:self.version];
  }
  return configuration;
}

- (NSString *)xctestPath
{
  return [FBControlCoreGlobalConfiguration.developerDirectory
    stringByAppendingPathComponent:@"Platforms/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest"];
}

@end
