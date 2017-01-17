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

#import "FBXCTestConfiguration.h"
#import "FBXCTestLogger.h"
#import "FBXCTestError.h"
#import "FBXCTestDestination.h"

@interface FBXCTestSimulatorFetcher ()

@property (nonatomic, strong, readonly) FBXCTestConfiguration *configuration;
@property (nonatomic, strong, readonly) FBSimulatorConfiguration *simulatorConfiguration;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBXCTestSimulatorFetcher

+ (instancetype)withConfiguration:(FBXCTestConfiguration *)configuration error:(NSError **)error
{
  id<FBControlCoreLogger> logger = configuration.logger;
  FBSimulatorControlConfiguration *controlConfiguration = [FBSimulatorControlConfiguration
    configurationWithDeviceSetPath:nil
    options:FBSimulatorManagementOptionsKillAllOnFirstStart];

  NSError *innerError = nil;
  FBSimulatorControl *simulatorControl = [FBSimulatorControl withConfiguration:controlConfiguration logger:configuration.logger error:&innerError];
  if (!simulatorControl) {
    return [FBXCTestError failWithError:innerError errorOut:error];
  }
  FBXCTestDestinationiPhoneSimulator *destination = (FBXCTestDestinationiPhoneSimulator *)configuration.destination;
  if (![destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a Simulator Destination", configuration.destination]
      fail:error];
  }

  return [[self alloc] initWithConfiguration:configuration simulatorConfiguration:destination.simulatorConfiguration simulatorControl:simulatorControl logger:logger];
}

- (instancetype)initWithConfiguration:(FBXCTestConfiguration *)configuration simulatorConfiguration:(FBSimulatorConfiguration *)simulatorConfiguration simulatorControl:(FBSimulatorControl *)simulatorControl logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _simulatorConfiguration = simulatorConfiguration;
  _simulatorControl = simulatorControl;
  _logger = logger;

  return self;
}

- (nullable FBSimulator *)fetchSimulatorForWithError:(NSError **)error
{
  return [self.configuration isKindOfClass:FBApplicationTestConfiguration.class]
    ? [self fetchSimulatorForApplicationTestsWithError:error]
    : [self fetchSimulatorForLogicTestWithError:error];
}

- (nullable FBSimulator *)fetchSimulatorForLogicTestWithError:(NSError **)error
{
  return [self.simulatorControl.pool
    allocateSimulatorWithConfiguration:self.simulatorConfiguration
    options:FBSimulatorAllocationOptionsReuse | FBSimulatorAllocationOptionsShutdownOnAllocate | FBSimulatorAllocationOptionsCreate
    error:error];
}

- (nullable FBSimulator *)fetchSimulatorForApplicationTestsWithError:(NSError **)error
{
  FBSimulator *simulator = [self fetchSimulatorForLogicTestWithError:error];
  if (!simulator) {
    return nil;
  }

  FBSimulatorBootConfiguration *bootConfiguration = [[FBSimulatorBootConfiguration
    defaultConfiguration]
    withOptions:FBSimulatorBootOptionsEnableDirectLaunch];

  if (![[FBSimulatorBootStrategy withConfiguration:bootConfiguration simulator:simulator] boot:error]) {
    [self.logger logFormat:@"Failed to boot simulator: %@", *error];
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
