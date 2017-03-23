/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControlTestCase.h"

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBSimulatorControlAssertions.h"

static NSString *const DeviceSetEnvKey = @"FBSIMULATORCONTROL_DEVICE_SET";
static NSString *const DeviceSetEnvDefault = @"default";
static NSString *const DeviceSetEnvCustom = @"custom";

static NSString *const LaunchTypeEnvKey = @"FBSIMULATORCONTROL_LAUNCH_TYPE";
static NSString *const LaunchTypeSimulatorApp = @"simulator_app";
static NSString *const LaunchTypeDirect = @"direct";

static NSString *const RecordVideoEnvKey = @"FBSIMULATORCONTROL_RECORD_VIDEO";

@interface FBSimulatorControlTestCase ()

@end

@implementation FBSimulatorControlTestCase

@synthesize control = _control;
@synthesize assert = _assert;

+ (void)initialize
{
  if (!NSProcessInfo.processInfo.environment[FBControlCoreStderrLogging]) {
    setenv(FBControlCoreStderrLogging.UTF8String, "YES", 1);
  }
  if (!NSProcessInfo.processInfo.environment[FBControlCoreDebugLogging]) {
    setenv(FBControlCoreDebugLogging.UTF8String, "NO", 1);
  }

  [FBControlCoreGlobalConfiguration.defaultLogger logFormat:@"Current Configuration => %@", FBControlCoreGlobalConfiguration.description];
  [FBSimulatorControlFrameworkLoader loadPrivateFrameworksOrAbort];
}

#pragma mark Property Overrides

- (FBSimulatorControl *)control
{
  if (!_control) {
    FBSimulatorControlConfiguration *configuration = [FBSimulatorControlConfiguration
      configurationWithDeviceSetPath:self.deviceSetPath
      options:self.managementOptions];

    NSError *error;
    FBSimulatorControl *control = [FBSimulatorControl withConfiguration:configuration error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(control);
    _control = control;
    _assert = [FBSimulatorControlNotificationAssertions withTestCase:self pool:control.pool];
  }
  return _control;
}

- (FBSimulatorControlNotificationAssertions *)assert
{
  XCTAssertNotNil(_assert, @"-[FBSimulatorControlTestCase control] should be called before -[FBSimulatorControlTestCase assert]");
  return _assert;
}

#pragma mark Configuration

+ (BOOL)isRunningOnTravis
{
  if (NSProcessInfo.processInfo.environment[@"TRAVIS"]) {
    NSLog(@"Running in Travis environment, skipping test");
    return YES;
  }
  return NO;
}

+ (BOOL)useDirectLaunching
{
  return ![NSProcessInfo.processInfo.environment[LaunchTypeEnvKey] isEqualToString:LaunchTypeSimulatorApp];
}

+ (FBSimulatorBootOptions)launchOptions
{
  FBSimulatorBootOptions options = 0;
  if (self.useDirectLaunching) {
    options = options | FBSimulatorBootOptionsEnableDirectLaunch;
  }
  return options;
}

+ (FBVideoEncoderConfiguration *)defaultEncoderConfiguration
{
  return [NSProcessInfo.processInfo.environment[RecordVideoEnvKey] boolValue]
    ? [FBVideoEncoderConfiguration withOptions:FBVideoEncoderConfiguration.defaultConfiguration.options | FBVideoEncoderOptionsAutorecord]
    : [FBVideoEncoderConfiguration defaultConfiguration];
}

+ (FBFramebufferConfiguration *)defaultFramebufferConfiguration
{
  return [FBFramebufferConfiguration.defaultConfiguration withEncoder:self.defaultEncoderConfiguration];
}

+ (NSString *)defaultDeviceSetPath
{
  NSString *value = NSProcessInfo.processInfo.environment[DeviceSetEnvKey];
  if ([value isEqualToString:DeviceSetEnvCustom]) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"FBSimulatorControlSimulatorLaunchTests_CustomSet"];
  }
  return nil;
}

+ (FBSimulatorBootConfiguration *)defaultLaunchConfiguration
{
  return [[FBSimulatorBootConfiguration
    withOptions:self.launchOptions]
    withFramebuffer:self.defaultFramebufferConfiguration];
}

#pragma mark XCTestCase

- (void)setUp
{
  self.continueAfterFailure = NO;
  self.managementOptions = FBSimulatorManagementOptionsKillSpuriousSimulatorsOnFirstStart | FBSimulatorManagementOptionsIgnoreSpuriousKillFail;
  self.allocationOptions = FBSimulatorAllocationOptionsReuse | FBSimulatorAllocationOptionsCreate | FBSimulatorAllocationOptionsEraseOnAllocate;
  self.simulatorConfiguration = [FBSimulatorConfiguration withDeviceModel:FBDeviceModeliPhone5];
  self.simulatorLaunchConfiguration = FBSimulatorControlTestCase.defaultLaunchConfiguration;
  self.deviceSetPath = FBSimulatorControlTestCase.defaultDeviceSetPath;
}

- (void)tearDown
{
  [self.control.pool.set killAllWithError:nil];
  _control = nil;
  _assert = nil;
}

@end
