/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

+ (void)initialize
{
  if (!NSProcessInfo.processInfo.environment[FBControlCoreStderrLogging]) {
    setenv(FBControlCoreStderrLogging.UTF8String, "YES", 1);
  }
  if (!NSProcessInfo.processInfo.environment[FBControlCoreDebugLogging]) {
    setenv(FBControlCoreDebugLogging.UTF8String, "NO", 1);
  }

  [FBControlCoreGlobalConfiguration.defaultLogger logFormat:@"Current Configuration => %@", FBControlCoreGlobalConfiguration.description];
  [FBSimulatorControlFrameworkLoader.essentialFrameworks loadPrivateFrameworksOrAbort];
}

#pragma mark Property Overrides

- (FBSimulatorControl *)control
{
  if (!_control) {
    FBSimulatorControlConfiguration *configuration = [FBSimulatorControlConfiguration
      configurationWithDeviceSetPath:self.deviceSetPath
      logger:nil
      reporter:nil];

    NSError *error;
    FBSimulatorControl *control = [FBSimulatorControl withConfiguration:configuration error:&error];
    XCTAssertNil(error);
    XCTAssertNotNil(control);
    _control = control;
  }
  return _control;
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

+ (FBSimulatorBootOptions)bootOptions
{
  FBSimulatorBootOptions options = 0;
  if (self.useDirectLaunching) {
    options = options | FBSimulatorBootOptionsTieToProcessLifecycle;
  }
  return options;
}

+ (NSString *)defaultDeviceSetPath
{
  NSString *value = NSProcessInfo.processInfo.environment[DeviceSetEnvKey];
  if ([value isEqualToString:DeviceSetEnvCustom]) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"FBSimulatorControlSimulatorLaunchTests_CustomSet"];
  }
  return nil;
}

+ (FBSimulatorBootConfiguration *)defaultBootConfiguration
{
  return [[FBSimulatorBootConfiguration alloc] initWithOptions:self.bootOptions environment:@{}];
}

#pragma mark XCTestCase

- (void)setUp
{
  self.continueAfterFailure = NO;
  self.simulatorConfiguration = [FBSimulatorConfiguration.defaultConfiguration withDeviceModel:FBDeviceModeliPhone8];
  self.bootConfiguration = [[FBSimulatorBootConfiguration alloc] initWithOptions:FBSimulatorControlTestCase.bootOptions environment:@{}];
  self.deviceSetPath = FBSimulatorControlTestCase.defaultDeviceSetPath;
}

- (void)tearDown
{
  [[self.control.set shutdownAll] await:nil];
  _control = nil;
}

@end
