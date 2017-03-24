/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorBootStrategy.h"

#import <Cocoa/Cocoa.h>

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDevice+Removed.h>
#import <CoreSimulator/SimDeviceType.h>

#import <SimulatorBridge/SimulatorBridge-Protocol.h>
#import <SimulatorBridge/SimulatorBridge.h>

#import <SimulatorKit/SimDeviceFramebufferService.h>

#import <FBControlCore/FBControlCore.h>

#import "FBFramebuffer.h"
#import "FBFramebufferConfiguration.h"
#import "FBFramebufferConnectStrategy.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorConnection.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorHID.h"
#import "FBSimulatorBootConfiguration+Helpers.h"
#import "FBSimulatorBootConfiguration.h"
#import "FBSimulatorLaunchCtl.h"
#import "FBSimulatorProcessFetcher.h"

@interface FBSimulatorBootStrategy ()

@property (nonatomic, strong, readonly, nonnull) FBSimulatorBootConfiguration *configuration;
@property (nonatomic, strong, readonly, nonnull) FBSimulator *simulator;

- (FBSimulatorConnection *)performBootWithError:(NSError **)error;

@end

@interface FBSimulatorBootStrategy_Direct : FBSimulatorBootStrategy

- (BOOL)shouldCreateFramebuffer;
- (NSDictionary<NSString *, id> *)bootOptions;

@end

@implementation FBSimulatorBootStrategy_Direct

- (FBSimulatorConnection *)performBootWithError:(NSError **)error
{
  // Create the Framebuffer (if required to do so).
  NSError *innerError = nil;
  FBFramebuffer *framebuffer = nil;
  if (self.shouldCreateFramebuffer) {
    FBFramebufferConfiguration *configuration = [self.configuration.framebuffer inSimulator:self.simulator];
    if (!configuration) {
      configuration = FBFramebufferConfiguration.defaultConfiguration;
      [self.simulator.logger logFormat:@"No Framebuffer Launch Configuration provided, but required. Using default of %@", configuration];
    }

    framebuffer = [[FBFramebufferConnectStrategy
      strategyWithConfiguration:configuration]
      connect:self.simulator error:&innerError];
    if (!framebuffer) {
      return [FBSimulatorError failWithError:innerError errorOut:error];
    }
  }

  // Create the HID Port
  FBSimulatorHID *hid = [FBSimulatorHID hidPortForSimulator:self.simulator error:&innerError];
  if (!hid) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  // Booting is simpler than the Simulator.app launch process since the caller calls CoreSimulator Framework directly.
  // Just pass in the options to ensure that the framebuffer service is registered when the Simulator is booted.
  NSDictionary<NSString *, id> *options = self.bootOptions;
  if (![self.simulator.device bootWithOptions:options error:&innerError]) {
    return [[[[FBSimulatorError
      describeFormat:@"Failed to boot Simulator with options %@", options]
      inSimulator:self.simulator]
      causedBy:innerError]
      fail:error];
  }

  return [[FBSimulatorConnection alloc] initWithSimulator:self.simulator framebuffer:framebuffer hid:hid];
}

- (BOOL)shouldCreateFramebuffer
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return NO;
}

- (SimDeviceFramebufferService *)createMainScreenService:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (NSDictionary<NSString *, id> *)bootOptions
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

@end

@interface FBSimulatorBootStrategy_Direct_Xcode7 : FBSimulatorBootStrategy_Direct

@end

@implementation FBSimulatorBootStrategy_Direct_Xcode7

- (BOOL)shouldCreateFramebuffer
{
  // A Framebuffer is required in Xcode 7 currently, otherwise any interface that uses the Mach Interface for 'Host Support' will fail/hang.
  return YES;
}

- (NSDictionary<NSString *, id> *)bootOptions
{
  // The 'register-head-services' option will attach the existing 'frameBufferService' when the Simulator is booted.
  // Simulator.app behaves similarly, except we can't peek at the Framebuffer as it is in a protected process since Xcode 7.
  // Prior to Xcode 6 it was possible to shim into the Simulator process but codesigning now prevents this https://gist.github.com/lawrencelomax/27bdc4e8a433a601008f

  return @{
    @"register-head-services" : @YES,
  };
}

@end

@interface FBSimulatorBootStrategy_Direct_Xcode8 : FBSimulatorBootStrategy_Direct

@end

@implementation FBSimulatorBootStrategy_Direct_Xcode8

- (BOOL)shouldCreateFramebuffer
{
  // Framebuffer connection is optional on Xcode 8 so we should use the appropriate configuration.
  return self.configuration.shouldConnectFramebuffer;
}

- (NSDictionary<NSString *, id> *)bootOptions
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

@interface FBSimulatorBootStrategy_Subprocess : FBSimulatorBootStrategy

- (BOOL)launchSimulatorProcessWithArguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment error:(NSError **)error;

@end

@implementation FBSimulatorBootStrategy_Subprocess

- (FBSimulatorConnection *)performBootWithError:(NSError **)error
{
  // Fetch the Boot Arguments & Environment
  NSError *innerError = nil;
  NSArray *arguments = [self.configuration xcodeSimulatorApplicationArgumentsForSimulator:self.simulator error:&innerError];
  if (!arguments) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to create boot args for Configuration %@", self.configuration]
      causedBy:innerError]
      fail:error];
  }
  // Add the UDID marker to the subprocess environment, so that it can be queried in any process.
  NSDictionary *environment = @{
    FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID : self.simulator.udid
  };

  // Launch the Simulator.app Process.
  if (![self launchSimulatorProcessWithArguments:arguments environment:environment error:&innerError]) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  // Expect the state of the simulator to be updated.
  BOOL didBoot = [self.simulator waitOnState:FBSimulatorStateBooted];
  if (!didBoot) {
    return [[[FBSimulatorError
      describeFormat:@"Timed out waiting for device to be Booted, got %@", self.simulator.device.stateString]
      inSimulator:self.simulator]
      fail:error];
  }

  // Expect the launch info for the process to exist.
  FBProcessInfo *containerApplication = [self.simulator.processFetcher simulatorApplicationProcessForSimDevice:self.simulator.device];
  if (!containerApplication) {
    return [[[FBSimulatorError
      describe:@"Could not obtain process info for container application"]
      inSimulator:self.simulator]
      fail:error];
  }
  [self.simulator.eventSink containerApplicationDidLaunch:containerApplication];

  return [[FBSimulatorConnection alloc] initWithSimulator:self.simulator framebuffer:nil hid:nil];
}

- (BOOL)launchSimulatorProcessWithArguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment error:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return NO;
}

@end

@interface FBSimulatorBootStrategy_Task : FBSimulatorBootStrategy_Subprocess

@end

@implementation FBSimulatorBootStrategy_Task

- (BOOL)launchSimulatorProcessWithArguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment error:(NSError **)error
{
  // Construct and start the task.
  FBTask *task = [[[[[FBTaskBuilder
    withLaunchPath:FBApplicationDescriptor.xcodeSimulator.binary.path]
    withArguments:arguments]
    withEnvironmentAdditions:environment]
    build]
    startAsynchronously];

  [self.simulator.eventSink terminationHandleAvailable:task];

  // Expect no immediate error.
  if (task.error) {
    return [[[[FBSimulatorError
      describe:@"Failed to Launch Simulator Process"]
      causedBy:task.error]
      inSimulator:self.simulator]
      failBool:error];
  }
  return YES;
}

@end

@interface FBSimulatorBootStrategy_Workspace : FBSimulatorBootStrategy_Subprocess

@end

@implementation FBSimulatorBootStrategy_Workspace

- (BOOL)launchSimulatorProcessWithArguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment error:(NSError **)error
{
  // The NSWorkspace API allows for arguments & environment to be provided to the launched application
  // Additionally, multiple Apps of the same application can be launched with the NSWorkspaceLaunchNewInstance option.
  NSURL *applicationURL = [NSURL fileURLWithPath:FBApplicationDescriptor.xcodeSimulator.path];
  NSDictionary *appLaunchConfiguration = @{
    NSWorkspaceLaunchConfigurationArguments : arguments,
    NSWorkspaceLaunchConfigurationEnvironment : environment,
  };

  NSError *innerError = nil;
  NSRunningApplication *application = [NSWorkspace.sharedWorkspace
    launchApplicationAtURL:applicationURL
    options:NSWorkspaceLaunchDefault | NSWorkspaceLaunchNewInstance | NSWorkspaceLaunchWithoutActivation
    configuration:appLaunchConfiguration
    error:&innerError];

  if (!application) {
    return [[[[FBSimulatorError
      describeFormat:@"Failed to launch simulator application %@ with configuration %@", applicationURL, appLaunchConfiguration]
      inSimulator:self.simulator]
      causedBy:innerError]
      failBool:error];
  }
  return YES;
}

@end

@implementation FBSimulatorBootStrategy

+ (instancetype)strategyWithConfiguration:(FBSimulatorBootConfiguration *)configuration simulator:(FBSimulator *)simulator
{
  if (configuration.shouldUseDirectLaunch) {
    return FBControlCoreGlobalConfiguration.isXcode8OrGreater
      ? [[FBSimulatorBootStrategy_Direct_Xcode8 alloc] initWithConfiguration:configuration simulator:simulator]
      : [[FBSimulatorBootStrategy_Direct_Xcode7 alloc] initWithConfiguration:configuration simulator:simulator];
  }
  if (configuration.shouldLaunchViaWorkspace) {
    return [[FBSimulatorBootStrategy_Workspace alloc] initWithConfiguration:configuration simulator:simulator];
  }
  return [[FBSimulatorBootStrategy_Task alloc] initWithConfiguration:configuration simulator:simulator];
}

- (instancetype)initWithConfiguration:(FBSimulatorBootConfiguration *)configuration simulator:(FBSimulator *)simulator
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _simulator = simulator;

  return self;
}

- (BOOL)boot:(NSError **)error
{
  // Return early depending on Simulator state.
  if (self.simulator.state == FBSimulatorStateBooted) {
    return YES;
  }
  if (self.simulator.state != FBSimulatorStateShutdown) {
    return [[[FBSimulatorError
      describeFormat:@"Cannot Boot Simulator when in %@ state", self.simulator.stateString]
      inSimulator:self.simulator]
      failBool:error];
  }

  // Perform the boot
  NSError *innerError = nil;
  FBSimulatorConnection *connection = [self performBootWithError:&innerError];
  if (!connection) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }

  // Fail when the bridge could not be connected.
  if (self.configuration.shouldConnectBridge) {
    FBSimulatorBridge *bridge = [connection connectToBridge:&innerError];
    if (!bridge) {
      return [FBSimulatorError failBoolWithError:innerError errorOut:error];
    }

    // Set the Location to a default location, when launched directly.
    // This is effectively done by Simulator.app by a NSUserDefault with for the 'LocationMode', even when the location is 'None'.
    // If the Location is set on the Simulator, then CLLocationManager will behave in a consistent manner inside launched Applications.
    [bridge setLocationWithLatitude:37.485023 longitude:-122.147911];
  }

  // Expect the launchd_sim process to be updated.
  if (![self launchdSimPresentWithAllRequiredServices:&innerError]) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }

  // Broadcast the availability of the new bridge.
  [self.simulator.eventSink connectionDidConnect:connection];

  return YES;
}

- (FBSimulatorConnection *)performBootWithError:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (FBProcessInfo *)launchdSimPresentWithAllRequiredServices:(NSError **)error
{
  FBSimulatorProcessFetcher *processFetcher = self.simulator.processFetcher;
  FBProcessInfo *launchdProcess = [processFetcher launchdProcessForSimDevice:self.simulator.device];
  if (!launchdProcess) {
    return [[[FBSimulatorError
      describe:@"Could not obtain process info for launchd_sim process"]
      inSimulator:self.simulator]
      fail:error];
  }
  [self.simulator.eventSink simulatorDidLaunch:launchdProcess];

  // Return early if we're not awaiting services.
  if ((self.configuration.options & FBSimulatorBootOptionsAwaitServices) != FBSimulatorBootOptionsAwaitServices) {
    return launchdProcess;
  }

  // Now wait for the services.
  NSSet<NSString *> *requiredServiceNames = [NSSet setWithArray:self.requiredLaunchdServicesToVerifyBooted];
  BOOL didStartAllRequiredServices = [NSRunLoop.mainRunLoop spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.slowTimeout untilTrue:^ BOOL {
    NSDictionary<NSString *, id> *services = [self.simulator.launchctl listServicesWithError:nil];
    if (!services) {
      return NO;
    }
    NSSet<id> *processIdentifiers = [NSSet setWithArray:[services objectsForKeys:requiredServiceNames.allObjects notFoundMarker:NSNull.null]];
    if ([processIdentifiers containsObject:NSNull.null]) {
      return NO;
    }
    return YES;
  }];
  if (!didStartAllRequiredServices) {
    return [[[FBSimulatorError
      describeFormat:@"Timed out waiting for all required services %@ to start", [FBCollectionInformation oneLineDescriptionFromArray:requiredServiceNames.allObjects]]
      inSimulator:self.simulator]
      fail:error];
  }

  return launchdProcess;
}

/*
 A Set of launchd_sim service names that are used to determine whether relevant System daemons are available after booting.

 There is a period of time between when CoreSimulator says that the Simulator is 'Booted'
 and when it is stable enough state to launch Applications/Daemons, these Service Names
 represent the Services that are known to signify readyness.

 @return the required Service Names.
 */
- (NSArray<NSString *> *)requiredLaunchdServicesToVerifyBooted
{
  FBControlCoreProductFamily family = self.simulator.productFamily;
  if (family == FBControlCoreProductFamilyiPhone || family == FBControlCoreProductFamilyiPad) {
    if (FBControlCoreGlobalConfiguration.isXcode8OrGreater) {
        NSArray *xcode8Services = @[@"com.apple.backboardd",
                                    @"com.apple.mobile.installd",
                                    @"com.apple.SimulatorBridge",
                                    @"com.apple.SpringBoard"];

        NSDecimalNumber *simulatorVersion = self.simulator.osVersion.number;
        NSDecimalNumber *iOS9 = [NSDecimalNumber decimalNumberWithString:@"9.0"];

        // medialibraryd does not load on simulators < iOS 9.
        if ([simulatorVersion isGreaterThanOrEqualTo:iOS9]) {
            NSMutableArray *mutable = [NSMutableArray arrayWithArray:xcode8Services];
            [mutable insertObject:@"com.apple.medialibraryd" atIndex:1];
            xcode8Services = [NSArray arrayWithArray:mutable];
        }

        return xcode8Services;
    }
  }
  if (family == FBControlCoreProductFamilyAppleWatch || family == FBControlCoreProductFamilyAppleTV) {
    if (FBControlCoreGlobalConfiguration.isXcode8OrGreater) {
      return @[
        @"com.apple.mobileassetd",
        @"com.apple.nsurlsessiond",
      ];
    }
    return @[
      @"com.apple.mobileassetd",
      @"com.apple.networkd",
    ];
  }
  return @[];
}

@end
