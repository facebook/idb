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
#import <XCTestBootstrap/XCTestBootstrap.h>

@interface FBXCTestSimulatorFetcher ()

@property (nonatomic, strong, readonly) FBSimulatorControl *simulatorControl;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBXCTestSimulatorFetcher

+ (nullable instancetype)fetcherWithWorkingDirectory:(NSString *)workingDirectory logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  NSString *setPath = [workingDirectory stringByAppendingPathComponent:@"sim"];
  FBSimulatorControlConfiguration *controlConfiguration = [FBSimulatorControlConfiguration
    configurationWithDeviceSetPath:setPath
    options:FBSimulatorManagementOptionsDeleteAllOnFirstStart];

  NSError *innerError = nil;
  FBSimulatorControl *simulatorControl = [FBSimulatorControl withConfiguration:controlConfiguration logger:logger error:&innerError];
  if (!simulatorControl) {
    return [FBXCTestError failWithError:innerError errorOut:error];
  }

  return [[self alloc] initWithSimulatorControl:simulatorControl logger:logger];
}

- (instancetype)initWithSimulatorControl:(FBSimulatorControl *)simulatorControl logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulatorControl = simulatorControl;
  _logger = logger;

  return self;
}

- (nullable FBSimulator *)fetchSimulatorForConfiguration:(FBXCTestConfiguration *)configuration error:(NSError **)error
{
  FBXCTestDestinationiPhoneSimulator *destination = (FBXCTestDestinationiPhoneSimulator *)configuration.destination;
  if (![destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a Simulator Destination", configuration.destination]
      fail:error];
  }

  return [configuration isKindOfClass:FBApplicationTestConfiguration.class]
    ? [self fetchSimulatorForApplicationTests:destination error:error]
    : [self fetchSimulatorForLogicTest:destination error:error];
}

- (nullable FBSimulator *)fetchSimulatorForLogicTest:(FBXCTestDestinationiPhoneSimulator *)destination error:(NSError **)error
{
  FBSimulatorConfiguration *configuration = [FBXCTestSimulatorFetcher configurationForDestination:destination];
  return [self.simulatorControl.pool
    allocateSimulatorWithConfiguration:configuration
    options:FBSimulatorAllocationOptionsCreate | FBSimulatorAllocationOptionsDeleteOnFree
    error:error];
}

- (nullable FBSimulator *)fetchSimulatorForApplicationTests:(FBXCTestDestinationiPhoneSimulator *)destination error:(NSError **)error
{
  FBSimulator *simulator = [self fetchSimulatorForLogicTest:destination error:error];
  if (!simulator) {
    return nil;
  }

  FBSimulatorBootConfiguration *bootConfiguration = [[FBSimulatorBootConfiguration
    defaultConfiguration]
    withOptions:FBSimulatorBootOptionsEnableDirectLaunch];

  if (![[FBSimulatorBootStrategy strategyWithConfiguration:bootConfiguration simulator:simulator] boot:error]) {
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

#pragma mark Private 

+ (FBSimulatorConfiguration *)configurationForDestination:(FBXCTestDestinationiPhoneSimulator *)destination
{
  FBSimulatorConfiguration *configuration = [FBSimulatorConfiguration defaultConfiguration];
  if (destination.model) {
    configuration = [configuration withDeviceModel:destination.model];
  }
  if (destination.version) {
    configuration = [configuration withOSNamed:destination.version];
  }
  return configuration;
}

@end
