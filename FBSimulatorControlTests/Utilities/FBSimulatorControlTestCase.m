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

static NSString *const DirectLaunchEnableVideoRecording = @"FBSIMULATORCONTROL_RECORD_VIDEO";

@interface FBSimulatorControlTestCase ()

@end

@implementation FBSimulatorControlTestCase

@synthesize control = _control;
@synthesize assert = _assert;

+ (void)initialize
{
  [FBSimulatorControlGlobalConfiguration setDefaultLoggerToASLWithStderrLogging:YES debugLogging:NO];
  [FBSimulatorControlGlobalConfiguration.defaultLogger logFormat:@"Current Configuration => %@", FBSimulatorControlGlobalConfiguration.description];
  [FBSimulatorControl loadPrivateFrameworksOrAbort];
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
    _assert = [FBSimulatorControlNotificationAssertions withTestCase:self pool:control.simulatorPool];
  }
  return _control;
}

- (FBSimulatorControlNotificationAssertions *)assert
{
  XCTAssertNotNil(_assert, @"-[FBSimulatorControlTestCase control] should be called before -[FBSimulatorControlTestCase assert]");
  return _assert;
}

#pragma mark Helper Actions

- (FBSimulator *)obtainSimulatorWithConfiguration:(FBSimulatorConfiguration *)configuration
{
  NSError *error = nil;
  FBSimulator *simulator = [self.control obtainSimulatorWithConfiguration:configuration options:self.allocationOptions error:&error];
  XCTAssertNil(error);
  XCTAssertNotNil(simulator);
  return simulator;
}

- (FBSimulator *)obtainSimulator
{
  return [self obtainSimulatorWithConfiguration:self.simulatorConfiguration];
}

- (FBSimulator *)obtainBootedSimulator
{
  FBSimulator *simulator = [self obtainSimulator];
  [self assertInteractionSuccessful:simulator.interact.bootSimulator];
  return simulator;
}

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
  if ([NSProcessInfo.processInfo.environment[LaunchTypeEnvKey] isEqualToString:LaunchTypeSimulatorApp]) {
    return NO;
  }
  return YES;
}

+ (NSString *)defaultDeviceSetPath
{
  NSString *value = NSProcessInfo.processInfo.environment[DeviceSetEnvKey];
  if ([value isEqualToString:DeviceSetEnvCustom]) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"FBSimulatorControlSimulatorLaunchTests_CustomSet"];
  }
  return nil;
}

+ (FBSimulatorLaunchConfiguration *)defaultLaunchConfiguration
{
  if (self.useDirectLaunching) {
    FBSimulatorLaunchOptions options = FBSimulatorLaunchOptionsEnableDirectLaunch;
    if (NSProcessInfo.processInfo.environment[DirectLaunchEnableVideoRecording]) {
      options = (options | FBSimulatorLaunchOptionsRecordVideo);
    }
    return [FBSimulatorLaunchConfiguration withOptions:options];
  }
  return FBSimulatorLaunchConfiguration.defaultConfiguration;
}

#pragma mark XCTestCase

- (void)setUp
{
  self.managementOptions = FBSimulatorManagementOptionsKillSpuriousSimulatorsOnFirstStart | FBSimulatorManagementOptionsIgnoreSpuriousKillFail;
  self.allocationOptions = FBSimulatorAllocationOptionsReuse | FBSimulatorAllocationOptionsCreate | FBSimulatorAllocationOptionsEraseOnAllocate;
  self.simulatorConfiguration = FBSimulatorConfiguration.iPhone5;
  self.simulatorLaunchConfiguration = FBSimulatorControlTestCase.defaultLaunchConfiguration;
  self.deviceSetPath = FBSimulatorControlTestCase.defaultDeviceSetPath;
}

- (void)tearDown
{
  [self.control.simulatorPool killAllWithError:nil];
  _control = nil;
  _assert = nil;
}

@end
