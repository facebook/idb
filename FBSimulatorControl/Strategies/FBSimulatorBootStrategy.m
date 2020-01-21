/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorBootStrategy.h"

#import <Cocoa/Cocoa.h>

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDevice+Removed.h>
#import <CoreSimulator/SimDeviceSet.h>
#import <CoreSimulator/SimDeviceType.h>

#import <SimulatorBridge/SimulatorBridge-Protocol.h>
#import <SimulatorBridge/SimulatorBridge.h>

#import <FBControlCore/FBControlCore.h>

#import "FBBundleDescriptor+Simulator.h"
#import "FBFramebuffer.h"
#import "FBFramebufferConfiguration.h"
#import "FBFramebufferConnectStrategy.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorConnection.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorHID.h"
#import "FBSimulatorSet.h"
#import "FBSimulatorBootConfiguration.h"
#import "FBSimulatorBootVerificationStrategy.h"
#import "FBSimulatorLaunchCtlCommands.h"
#import "FBSimulatorProcessFetcher.h"

@interface FBSimulatorBootConfiguration (FBSimulatorBootStrategy)

@end

@implementation FBSimulatorBootConfiguration (FBSimulatorBootStrategy)

- (BOOL)shouldUseDirectLaunch
{
  return (self.options & FBSimulatorBootOptionsEnableDirectLaunch) == FBSimulatorBootOptionsEnableDirectLaunch;
}

- (BOOL)shouldConnectFramebuffer
{
  return self.framebuffer != nil;
}

- (BOOL)shouldLaunchViaWorkspace
{
  return (self.options & FBSimulatorBootOptionsUseNSWorkspace) == FBSimulatorBootOptionsUseNSWorkspace;
}

- (BOOL)shouldConnectBridge
{
  // If the option is flagged it should be used.
  if ((self.options & FBSimulatorBootOptionsConnectBridge) == FBSimulatorBootOptionsConnectBridge) {
    return YES;
  }
  // In some versions of Xcode 8, it was possible that a direct launch without a bridge could mean applications would not launch.
  if (!FBXcodeConfiguration.isXcode9OrGreater && self.shouldUseDirectLaunch) {
    return YES;
  }
  return NO;
}

@end

/**
 Provides relevant options to CoreSimulator for Booting.
 */
@protocol FBCoreSimulatorBootOptions <NSObject>

/**
 YES if the Framebuffer should be created, NO otherwise.
 */
- (BOOL)shouldCreateFramebuffer:(FBSimulatorBootConfiguration *)configuration;

/**
 The Options to provide to the CoreSimulator API.
 */
- (NSDictionary<NSString *, id> *)bootOptions:(FBSimulatorBootConfiguration *)configuration;

@end

/**
 Provides an implementation of Launching a Simulator Application.
 */
@protocol FBSimulatorApplicationProcessLauncher <NSObject>

/**
 Launches the SimulatorApp Process.

 @param arguments the SimulatorApp process arguments.
 @param environment the environment for the process.
 @return YES if successful, NO otherwise.
 */
- (FBFuture<NSNull *> *)launchSimulatorProcessWithArguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment;

@end

/**
 Provides Launch Options to a Simulator.
 */
@protocol FBSimulatorGUIAppLauncherOptions <NSObject>

/**
 Creates and returns the arguments to pass to Xcode's Simulator.app for the receiver's configuration.

 @param configuration the configuration to base off.
 @param simulator the Simulator construct boot args for.
 @param error an error out for any error that occurs.
 @return an NSArray<NSString> of boot arguments, or nil if an error occurred.
 */
- (NSArray<NSString *> *)xcodeSimulatorApplicationArguments:(FBSimulatorBootConfiguration *)configuration simulator:(FBSimulator *)simulator error:(NSError **)error;

/**
 Determines whether the Simulator Application should be launched.

 @param configuration the configuration to use.
 @param simulator the Simulator.
 @preturn YES if the SimulatorApp should be launched, NO otherwise.
 */
- (BOOL)shouldLaunchSimulatorApplication:(FBSimulatorBootConfiguration *)configuration simulator:(FBSimulator *)simulator;

@end

@interface FBSimulatorGUIAppLauncher : NSObject

@property (nonatomic, strong, readonly) FBSimulatorBootConfiguration *configuration;
@property (nonatomic, strong, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) id<FBSimulatorApplicationProcessLauncher> launcher;
@property (nonatomic, strong, readonly) id<FBSimulatorGUIAppLauncherOptions> options;

@end

@interface FBCoreSimulatorBootStrategy : NSObject

@property (nonatomic, strong, readonly) FBSimulatorBootConfiguration *configuration;
@property (nonatomic, strong, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) id<FBCoreSimulatorBootOptions> options;

@end

@interface FBSimulatorBootStrategy ()

@property (nonatomic, strong, readonly) FBSimulatorBootConfiguration *configuration;
@property (nonatomic, strong, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) FBSimulatorGUIAppLauncher *appLauncher;
@property (nonatomic, strong, readonly) FBCoreSimulatorBootStrategy *coreSimulatorStrategy;

- (instancetype)initWithConfiguration:(FBSimulatorBootConfiguration *)configuration simulator:(FBSimulator *)simulator appLauncher:(FBSimulatorGUIAppLauncher *)appLauncher coreSimulatorStrategy:(FBCoreSimulatorBootStrategy *)coreSimulatorStrategy;

@end

@interface FBCoreSimulatorBootOptions_Xcode8 : NSObject <FBCoreSimulatorBootOptions>
@end

@interface FBCoreSimulatorBootOptions_Xcode9_10 : NSObject <FBCoreSimulatorBootOptions>
@end

@implementation FBCoreSimulatorBootOptions_Xcode8

- (BOOL)shouldCreateFramebuffer:(FBSimulatorBootConfiguration *)configuration
{
  // Framebuffer connection is optional on Xcode 8 so we should use the appropriate configuration.
  return configuration.shouldConnectFramebuffer;
}

- (NSDictionary<NSString *, id> *)bootOptions:(FBSimulatorBootConfiguration *)configuration
{
  // Since Xcode 8 Beta 5, 'simctl' uses the 'SIMULATOR_IS_HEADLESS' argument.
  return @{
    @"register-head-services" : @YES,
    @"env" : @{
      @"SIMULATOR_IS_HEADLESS" : @1,
    },
  };
}

@end

@implementation FBCoreSimulatorBootOptions_Xcode9_10

- (BOOL)shouldCreateFramebuffer:(FBSimulatorBootConfiguration *)configuration
{
  // Framebuffer connection is optional on Xcode 9 so we should use the appropriate configuration.
  return configuration.shouldConnectFramebuffer;
}

- (NSDictionary<NSString *, id> *)bootOptions:(FBSimulatorBootConfiguration *)configuration
{
  // "Persisting" means for the booted Simulator to live beyond the lifecycle of the process that calls the boot API.
  // This is the default for `simctl which boots the simulator and leaves it booted until 'shutdown' is called.
  // This is also possible in `simctl` if the undocumented `--wait` flag is passed after the Simulator's UDID.
  // If "Direct Launch" is enabled we *do not* want the Simulator to live beyond the lifecycle of the process calling boot
  // as this gives us cleaner teardown semantics for automated scenarios.
  return @{
    @"persist": @(!configuration.shouldUseDirectLaunch),
    @"env" : configuration.environment ?: @{},
  };
}

@end

@implementation FBCoreSimulatorBootStrategy

- (instancetype)initWithConfiguration:(FBSimulatorBootConfiguration *)configuration simulator:(FBSimulator *)simulator options:(id<FBCoreSimulatorBootOptions>)options
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _simulator = simulator;
  _options = options;

  return self;
}

- (FBFuture<FBSimulatorConnection *> *)performBoot
{
  // Only Boot with CoreSimulator when told to do so. Return early if not.
  if (!self.shouldBootWithCoreSimulator) {
    return [self.simulator connect];
  }

  // Create the Framebuffer (if required to do so).
  FBFuture *framebufferFuture = FBFuture.empty;
  if ([self.options shouldCreateFramebuffer:self.configuration]) {
    // If we require a Framebuffer, but don't have one provided, we should use the default one.
    FBFramebufferConfiguration *configuration = self.configuration.framebuffer;
    if (!configuration) {
      configuration = FBFramebufferConfiguration.defaultConfiguration;
      [self.simulator.logger logFormat:@"No Framebuffer Launch Configuration provided, but required. Using default of %@", configuration];
    }
    // Update it to include the relevant paths for *this* simulator.
    configuration = [configuration inSimulator:self.simulator];
    // Then connect to it.
    framebufferFuture = [[FBFramebufferConnectStrategy strategyWithConfiguration:configuration] connect:self.simulator];
  }

  // Create the HID Port
  FBFuture *hidFuture = [FBSimulatorHID hidForSimulator:self.simulator];

  return [[[FBFuture
    futureWithFutures:@[
      framebufferFuture,
      hidFuture,
    ]]
    onQueue:self.simulator.workQueue fmap:^(NSArray *results) {
      // Booting is simpler than the Simulator.app launch process since the caller calls CoreSimulator Framework directly.
      // Just pass in the options to ensure that the framebuffer service is registered when the Simulator is booted.
      return [[self bootSimulatorWithOptions:[self.options bootOptions:self.configuration]] mapReplace:results];
    }]
    onQueue:self.simulator.workQueue fmap:^(NSArray *results) {
      // Combine everything into the connection.
      FBFramebuffer *framebuffer = [results[0] isKindOfClass:NSNull.class] ? nil : results[0];;
      FBSimulatorHID *hid = results[1];
      return [self.simulator connectWithHID:hid framebuffer:framebuffer];
    }];
}

- (BOOL)shouldBootWithCoreSimulator
{
  // Always boot with CoreSimulator on Xcode 9
  if (FBXcodeConfiguration.isXcode9OrGreater) {
    return YES;
  }
  // Otherwise obey the direct launch config.
  return self.configuration.shouldUseDirectLaunch;
}

- (FBFuture<NSNull *> *)bootSimulatorWithOptions:(NSDictionary<NSString *, id> *)options
{
  FBMutableFuture<NSNull *> *future = FBMutableFuture.future;
  [self.simulator.device bootAsyncWithOptions:options completionQueue:self.simulator.workQueue completionHandler:^(NSError *error){
    if (error) {
      [future resolveWithError:error];
    } else {
      [future resolveWithResult:NSNull.null];
    }
  }];
  return future;
}

@end

@interface FBSimulatorApplicationProcessLauncher_Task : NSObject <FBSimulatorApplicationProcessLauncher>
@end

@interface FBSimulatorApplicationProcessLauncher_Workspace : NSObject <FBSimulatorApplicationProcessLauncher>
@end

@implementation FBSimulatorApplicationProcessLauncher_Task

- (FBFuture<NSNull *> *)launchSimulatorProcessWithArguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment;
{
  return [[[[[[FBTaskBuilder
    withLaunchPath:FBBundleDescriptor.xcodeSimulator.binary.path]
    withArguments:arguments]
    withEnvironmentAdditions:environment]
    start]
    rephraseFailure:@"Failed to Launch Simulator Process %@", [FBCollectionInformation oneLineDescriptionFromArray:arguments]]
    mapReplace:NSNull.null];
}

@end

@implementation FBSimulatorApplicationProcessLauncher_Workspace

- (FBFuture<NSNull *> *)launchSimulatorProcessWithArguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment
{
  // The NSWorkspace API allows for arguments & environment to be provided to the launched application
  // Additionally, multiple Apps of the same application can be launched with the NSWorkspaceLaunchNewInstance option.
  NSURL *applicationURL = [NSURL fileURLWithPath:FBBundleDescriptor.xcodeSimulator.path];
  NSDictionary *appLaunchConfiguration = @{
    NSWorkspaceLaunchConfigurationArguments : arguments,
    NSWorkspaceLaunchConfigurationEnvironment : environment,
  };

  NSError *error = nil;
  NSRunningApplication *application = [NSWorkspace.sharedWorkspace
    launchApplicationAtURL:applicationURL
    options:NSWorkspaceLaunchDefault | NSWorkspaceLaunchNewInstance | NSWorkspaceLaunchWithoutActivation
    configuration:appLaunchConfiguration
    error:&error];

  if (!application) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to launch simulator application %@ with configuration %@", applicationURL, appLaunchConfiguration]
      causedBy:error]
      failFuture];
  }
  return FBFuture.empty;
}

@end

@interface FBSimulatorGUIAppLauncherOptions_Xcode7 : NSObject <FBSimulatorGUIAppLauncherOptions>
@end

@implementation FBSimulatorGUIAppLauncherOptions_Xcode7

- (NSArray<NSString *> *)xcodeSimulatorApplicationArguments:(FBSimulatorBootConfiguration *)configuration simulator:(FBSimulator *)simulator error:(NSError **)error
{
  // These arguments are based on the NSUserDefaults that are serialized for the Simulator.app.
  // These can be seen with `defaults read com.apple.iphonesimulator` and has default location of ~/Library/Preferences/com.apple.iphonesimulator.plist
  // NSUserDefaults for any application can be overriden in the NSArgumentDomain:
  // https://developer.apple.com/library/ios/documentation/Cocoa/Conceptual/UserDefaults/AboutPreferenceDomains/AboutPreferenceDomains.html#//apple_ref/doc/uid/10000059i-CH2-96930
  NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithArray:@[
    @"--args",
    @"-CurrentDeviceUDID", simulator.udid,
    @"-ConnectHardwareKeyboard", @"0",
  ]];
  FBScale scale = configuration.scale;
  if (scale) {
    [arguments addObjectsFromArray:@[
      [self lastScaleCommandLineSwitchForSimulator:simulator], scale,
    ]];
  }

  NSString *setPath = simulator.set.deviceSet.setPath;
  if (setPath) {
    [arguments addObjectsFromArray:@[@"-DeviceSetPath", setPath]];
  }
  return [arguments copy];
}

- (BOOL)shouldLaunchSimulatorApplication:(FBSimulatorBootConfiguration *)configuration simulator:(FBSimulator *)simulator
{
  // Only launch Simulator App if not using CoreSimulator to launch.
  return !configuration.shouldUseDirectLaunch;
}

- (NSString *)lastScaleCommandLineSwitchForSimulator:(FBSimulator *)simulator
{
  return [NSString stringWithFormat:@"-SimulatorWindowLastScale-%@", simulator.device.deviceTypeIdentifier];
}

@end

@interface FBSimulatorGUIAppLauncherOptions_Xcode9 : NSObject <FBSimulatorGUIAppLauncherOptions>

@end

@implementation FBSimulatorGUIAppLauncherOptions_Xcode9

- (NSArray<NSString *> *)xcodeSimulatorApplicationArguments:(FBSimulatorBootConfiguration *)configuration simulator:(FBSimulator *)simulator error:(NSError **)error
{
  NSString *setPath = simulator.set.deviceSet.setPath;
  return @[
    @"--args",
    @"-DeviceSetPath", setPath, // Always pass the Device Set Path.
    @"-DetatchOnAppQuit", @"0", // Shutdown Sims on Quitting the App, just like in < Xcode 9.
    @"-DetachOnWindowClose", @"0",  // As above, but for windows.
    @"-AttachBootedOnStart", @"1",  // Always attach to running sims, so that they have an open window.
    @"-StartLastDeviceOnLaunch", @"0", // *never* let SimulatorApp boot on our behalf.
 ];
}

- (BOOL)shouldLaunchSimulatorApplication:(FBSimulatorBootConfiguration *)configuration simulator:(FBSimulator *)simulator
{
  // With Xcode 9 Direct-Launch Only, don't boot a Simulator App.
  if (configuration.shouldUseDirectLaunch) {
    return NO;
  }
  // Find a Simulator App for the current set if one exists, if it does exist then don't launch one.
  NSString *setPath = simulator.set.deviceSet.setPath;
  FBProcessInfo *applicationProcess = simulator.processFetcher.simulatorApplicationProcessesByDeviceSetPath[setPath];
  if (applicationProcess) {
    [simulator.logger logFormat:@"Existing Simulator Application %@ found, not re-launching one for this device set", applicationProcess];
    return NO;
  }
  // Otherwise we should launch one
  [simulator.logger logFormat:@"No Simulator Application found for device set '%@', launching a Simulator App for %@", setPath, simulator];
  return YES;
}

@end


@implementation FBSimulatorGUIAppLauncher

- (instancetype)initWithConfiguration:(FBSimulatorBootConfiguration *)configuration simulator:(FBSimulator *)simulator launcher:(id<FBSimulatorApplicationProcessLauncher>)launcher options:(id<FBSimulatorGUIAppLauncherOptions>)options
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _simulator = simulator;
  _launcher = launcher;
  _options = options;

  return self;
}

- (FBFuture<NSNull *> *)launchSimulatorApplication
{
  // Return early if we shouldn't launch the Application
  if (![self.options shouldLaunchSimulatorApplication:self.configuration simulator:self.simulator]) {
    return FBFuture.empty;
  }

  // Fetch the Boot Arguments & Environment
  NSError *error = nil;
  NSArray *arguments = [self.options xcodeSimulatorApplicationArguments:self.configuration simulator:self.simulator error:&error];
  if (!arguments) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to create boot args for Configuration %@", self.configuration]
      causedBy:error]
      failFuture];
  }
  // Add the UDID marker to the subprocess environment, so that it can be queried in any process.
  NSDictionary *environment = @{
    FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID : self.simulator.udid,
    FBSimulatorControlSimulatorLaunchEnvironmentDeviceSetPath : self.simulator.set.deviceSet.setPath,
  };

  // Launch the Simulator.app Process.
  return [[[self.launcher
    launchSimulatorProcessWithArguments:arguments environment:environment]
    onQueue:self.simulator.workQueue fmap:^(NSNull *_) {
      return [self.simulator resolveState:FBiOSTargetStateBooted];
    }]
    onQueue:self.simulator.workQueue fmap:^ FBFuture<NSNull *> * (NSNull *_) {
      FBProcessInfo *containerApplication = [self.simulator.processFetcher simulatorApplicationProcessForSimDevice:self.simulator.device];
      if (!containerApplication) {
        return [[FBSimulatorError
          describe:@"Could not obtain process info for container application"]
          failFuture];
      }
      [self.simulator.eventSink containerApplicationDidLaunch:containerApplication];
      return FBFuture.empty;
    }];
}

@end

@implementation FBSimulatorBootStrategy

+ (instancetype)strategyWithConfiguration:(FBSimulatorBootConfiguration *)configuration simulator:(FBSimulator *)simulator
{
  id<FBCoreSimulatorBootOptions> coreSimulatorOptions = [self coreSimulatorBootOptions];
  FBCoreSimulatorBootStrategy *coreSimulatorStrategy = [[FBCoreSimulatorBootStrategy alloc] initWithConfiguration:configuration simulator:simulator options:coreSimulatorOptions];
  id<FBSimulatorApplicationProcessLauncher> launcher = [self applicationProcessLauncherWithConfiguration:configuration];
  id<FBSimulatorGUIAppLauncherOptions> applicationOptions = [self applicationLaunchOptions];
  FBSimulatorGUIAppLauncher *appLauncher = [[FBSimulatorGUIAppLauncher alloc] initWithConfiguration:configuration simulator:simulator launcher:launcher options:applicationOptions];
  return [[FBSimulatorBootStrategy alloc] initWithConfiguration:configuration simulator:simulator appLauncher:appLauncher coreSimulatorStrategy:coreSimulatorStrategy];
}

+ (id<FBCoreSimulatorBootOptions>)coreSimulatorBootOptions
{
  if (FBXcodeConfiguration.isXcode9OrGreater) {
    return [FBCoreSimulatorBootOptions_Xcode9_10 new];
  } else {
    return [FBCoreSimulatorBootOptions_Xcode8 new];
  }
}

+ (id<FBSimulatorApplicationProcessLauncher>)applicationProcessLauncherWithConfiguration:(FBSimulatorBootConfiguration *)configuration
{
  return configuration.shouldLaunchViaWorkspace
    ? [FBSimulatorApplicationProcessLauncher_Workspace new]
    : [FBSimulatorApplicationProcessLauncher_Task new];
}

+ (id<FBSimulatorGUIAppLauncherOptions>)applicationLaunchOptions
{
  return FBXcodeConfiguration.isXcode9OrGreater
    ? [FBSimulatorGUIAppLauncherOptions_Xcode9 new]
    : [FBSimulatorGUIAppLauncherOptions_Xcode7 new];
}

- (instancetype)initWithConfiguration:(FBSimulatorBootConfiguration *)configuration simulator:(FBSimulator *)simulator appLauncher:(FBSimulatorGUIAppLauncher *)appLauncher coreSimulatorStrategy:(FBCoreSimulatorBootStrategy *)coreSimulatorStrategy
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _simulator = simulator;
  _appLauncher = appLauncher;
  _coreSimulatorStrategy = coreSimulatorStrategy;

  return self;
}

- (FBFuture<NSNull *> *)boot
{
  // Return early depending on Simulator state.
  if (self.simulator.state == FBiOSTargetStateBooted) {
    return FBFuture.empty;
  }
  if (self.simulator.state != FBiOSTargetStateShutdown) {
    return [[[FBSimulatorError
      describeFormat:@"Cannot Boot Simulator when in %@ state", self.simulator.stateString]
      inSimulator:self.simulator]
      failFuture];
  }

  // Boot via CoreSimulator.
  return [[[[[self.coreSimulatorStrategy
    performBoot]
    onQueue:self.simulator.workQueue fmap:^(FBSimulatorConnection *connection) {
      return [[self.appLauncher launchSimulatorApplication] mapReplace:connection];
    }]
    onQueue:self.simulator.workQueue fmap:^(FBSimulatorConnection *connection) {
      if (!self.configuration.shouldConnectBridge) {
        return [FBFuture futureWithResult:connection];
      }
      return [[connection
        connectToBridge]
        onQueue:self.simulator.workQueue map:^(FBSimulatorBridge *bridge) {
          // Set the Location to a default location, when launched directly.
          // This is effectively done by Simulator.app by a NSUserDefault with for the 'LocationMode', even when the location is 'None'.
          // If the Location is set on the Simulator, then CLLocationManager will behave in a consistent manner inside launched Applications.
          [bridge setLocationWithLatitude:37.485023 longitude:-122.147911];

          // Match the return type of the return-early case.
          return connection;
        }];
    }]
    onQueue:self.simulator.workQueue fmap:^(FBSimulatorConnection *connection) {
      return [self verifySimulatorIsBooted];
    }]
    mapReplace:NSNull.null];
}

- (FBFuture<FBProcessInfo *> *)verifySimulatorIsBooted
{
  FBSimulatorProcessFetcher *processFetcher = self.simulator.processFetcher;
  FBProcessInfo *launchdProcess = [processFetcher launchdProcessForSimDevice:self.simulator.device];
  if (!launchdProcess) {
    return [[[FBSimulatorError
      describe:@"Could not obtain process info for launchd_sim process"]
      inSimulator:self.simulator]
      failFuture];
  }
  [self.simulator.eventSink simulatorDidLaunch:launchdProcess];

  // Return early if we're not awaiting services.
  if ((self.configuration.options & FBSimulatorBootOptionsVerifyUsable) != FBSimulatorBootOptionsVerifyUsable) {
    return [FBFuture futureWithResult:launchdProcess];
  }

  // Now wait for the services.
  return [[[FBSimulatorBootVerificationStrategy
    strategyWithSimulator:self.simulator]
    verifySimulatorIsBooted]
    mapReplace:launchdProcess];
}

@end
