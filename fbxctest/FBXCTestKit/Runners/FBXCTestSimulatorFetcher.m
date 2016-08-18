/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestSimulatorFetcher.h"

#import <FBSimulatorControl/FBSimulatorControl.h>

#import "FBTestRunConfiguration.h"
#import "FBXCTestLogger.h"
#import "FBXCTestError.h"

@interface FBXCTestSimulatorFetcher ()

@property (nonatomic, strong, readonly) FBTestRunConfiguration *configuration;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBXCTestSimulatorFetcher

+ (instancetype)withConfiguration:(FBTestRunConfiguration *)configuration error:(NSError **)error
{
  NSString *setPath = [configuration.workingDirectory stringByAppendingPathComponent:@"sim"];
  id<FBControlCoreLogger> logger = configuration.logger;
  FBSimulatorControlConfiguration *controlConfiguration = [FBSimulatorControlConfiguration
    configurationWithDeviceSetPath:setPath
    options:FBSimulatorManagementOptionsDeleteAllOnFirstStart];

  NSError *innerError = nil;
  FBSimulatorControl *simulatorControl = [FBSimulatorControl withConfiguration:controlConfiguration logger:configuration.logger error:&innerError];
  if (!simulatorControl) {
    return [FBXCTestError failWithError:innerError errorOut:error];
  }

  return [[self alloc] initWithConfiguration:configuration simulatorControl:simulatorControl logger:logger];
}

- (instancetype)initWithConfiguration:(FBTestRunConfiguration *)configuration simulatorControl:(FBSimulatorControl *)simulatorControl logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _simulatorControl = simulatorControl;
  _logger = logger;

  return self;
}

- (nullable FBSimulator *)fetchSimulatorForLogicTestWithError:(NSError **)error
{
  return [self.simulatorControl.pool
    allocateSimulatorWithConfiguration:self.configuration.targetDeviceConfiguration
    options:FBSimulatorAllocationOptionsCreate | FBSimulatorAllocationOptionsDeleteOnFree
    error:error];
}

- (nullable FBSimulator *)fetchSimulatorForApplicationTestsWithError:(NSError **)error
{
  FBSimulator *simulator = [self fetchSimulatorForLogicTestWithError:error];
  if (!simulator) {
    return nil;
  }

  FBSimulatorLaunchConfiguration *launchConfiguration = [[FBSimulatorLaunchConfiguration
    defaultConfiguration]
    withOptions:FBSimulatorLaunchOptionsEnableDirectLaunch];

  FBInteraction *launchInteraction = [[simulator.interact
    prepareForLaunch:launchConfiguration]
    bootSimulator:launchConfiguration];

  if (![launchInteraction perform:error]) {
    [self.configuration.logger logFormat:@"Failed to boot simulator: %@", *error];
    return nil;
  }
  return simulator;
}

- (BOOL)returnSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  if (![self.simulatorControl.pool freeSimulator:simulator error:error]) {
    return NO;
  }
  return YES;
}

@end
