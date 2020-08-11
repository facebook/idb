/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
  NSString *setPath = [self setPathForWorkingDirectory:workingDirectory logger:logger];
  FBSimulatorControlConfiguration *controlConfiguration = [FBSimulatorControlConfiguration
    configurationWithDeviceSetPath:setPath
    options:0
    logger:logger
    reporter:nil];

  NSError *innerError = nil;
  FBSimulatorControl *simulatorControl = [FBSimulatorControl withConfiguration:controlConfiguration error:&innerError];
  if (!simulatorControl) {
    return [FBXCTestError failWithError:innerError errorOut:error];
  }

  return [[self alloc] initWithSimulatorControl:simulatorControl logger:logger];
}

+ (NSString *)setPathForWorkingDirectory:(NSString *)workingDirectory logger:(id<FBControlCoreLogger>)logger
{
  NSOperatingSystemVersion xcodeVersion = FBXcodeConfiguration.xcodeVersion;
  if (xcodeVersion.majorVersion == 11 && xcodeVersion.minorVersion >= 5) {
    [logger logFormat:@"CoreSimulatorService can wedge with custom sets in Xcode %@, using the default set", FBXcodeConfiguration.xcodeVersionNumber];
    return nil;
  }
  NSString *fallbackSetPath = [workingDirectory stringByAppendingPathComponent:@"sim"];
  NSString *xctestDevicesSet = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Developer/XCTestDevices"];
  BOOL isDirectory = NO;
  if (![NSFileManager.defaultManager fileExistsAtPath:xctestDevicesSet isDirectory:&isDirectory]) {
    [logger logFormat:@"%@ is not present. Falling back to using set path relative to working directory %@", xctestDevicesSet, fallbackSetPath];
    return fallbackSetPath;
  }
  if (!isDirectory) {
    [logger logFormat:@"%@ is not a directory. Falling back to using set path relative to working directory %@", xctestDevicesSet, fallbackSetPath];
    return fallbackSetPath;
  }
  [logger logFormat:@"%@ exists, using it for fbxctest's simulator set", xctestDevicesSet];
  return xctestDevicesSet;
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
  return [self.simulatorControl.set createSimulatorWithConfiguration:configuration];
}

- (FBFuture<FBSimulator *> *)fetchSimulatorForApplicationTest:(FBXCTestDestinationiPhoneSimulator *)destination
{
  FBSimulatorBootConfiguration *bootConfiguration = [[FBSimulatorBootConfiguration
    defaultConfiguration]
    withOptions:FBSimulatorBootOptionsEnableDirectLaunch | FBSimulatorBootOptionsVerifyUsable];

  return [[self
    fetchSimulatorForLogicTest:destination]
    onQueue:dispatch_get_main_queue() fmap:^(FBSimulator *simulator) {
      return [[simulator bootWithConfiguration:bootConfiguration] mapReplace:simulator];
    }];
}

- (FBFuture<NSNull *> *)returnSimulator:(FBSimulator *)simulator
{
  return [[self.simulatorControl.set deleteSimulator:simulator] mapReplace:NSNull.null];
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
