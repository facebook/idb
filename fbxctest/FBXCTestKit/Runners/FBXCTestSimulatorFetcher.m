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

#import "FBXCTestCommandLine.h"
#import "FBXCTestDestination.h"

@interface FBXCTestSimulatorFetcher ()

@property (nonatomic, strong, readonly) FBSimulatorControl *simulatorControl;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBXCTestSimulatorFetcher

#pragma mark Initializers

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

#pragma mark Public Methods

- (FBFuture<FBSimulator *> *)fetchSimulatorForCommandLine:(FBXCTestCommandLine *)commandLine
{
  FBXCTestDestinationiPhoneSimulator *destination = (FBXCTestDestinationiPhoneSimulator *) commandLine.destination;
  if (![destination isKindOfClass:FBXCTestDestinationiPhoneSimulator.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a Simulator Destination", destination]
      failFuture];
  }

  if ([commandLine.configuration isKindOfClass:FBTestManagerTestConfiguration.class]) {
    return [self fetchSimulatorForApplicationTest:destination];
  }
  return [self fetchSimulatorForLogicTest:destination];
}

- (FBFuture<FBSimulator *> *)fetchSimulatorForLogicTest:(FBXCTestDestinationiPhoneSimulator *)destination
{
  FBSimulatorConfiguration *configuration = [FBXCTestSimulatorFetcher configurationForDestination:destination];
  return [self.simulatorControl.pool
    allocateSimulatorWithConfiguration:configuration
    options:FBSimulatorAllocationOptionsCreate | FBSimulatorAllocationOptionsDeleteOnFree];
}

- (FBFuture<FBSimulator *> *)fetchSimulatorForApplicationTest:(FBXCTestDestinationiPhoneSimulator *)destination
{
  FBSimulatorBootConfiguration *bootConfiguration = [[FBSimulatorBootConfiguration
    defaultConfiguration]
    withOptions:FBSimulatorBootOptionsEnableDirectLaunch];

  return [[self
    fetchSimulatorForLogicTest:destination]
    onQueue:dispatch_get_main_queue() fmap:^(FBSimulator *simulator) {
      return [[simulator bootWithConfiguration:bootConfiguration] mapReplace:simulator];
    }];
}

- (FBFuture<NSNull *> *)returnSimulator:(FBSimulator *)simulator
{
  return [self.simulatorControl.pool freeSimulator:simulator];
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
