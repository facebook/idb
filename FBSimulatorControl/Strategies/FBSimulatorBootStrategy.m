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
#import "FBProcessFetcher+Simulators.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorConnection.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorLaunchCtl.h"
#import "FBSimulatorLaunchConfiguration+Helpers.h"
#import "FBSimulatorLaunchConfiguration.h"
#import "FBSimulatorHID.h"

@interface FBSimulatorBootStrategy ()

@property (nonatomic, strong, readonly, nonnull) FBSimulatorLaunchConfiguration *configuration;
@property (nonatomic, strong, readonly, nonnull) FBSimulator *simulator;

- (FBSimulatorConnection *)performBootWithError:(NSError **)error;

@end

@interface FBSimulatorBootStrategy_Direct : FBSimulatorBootStrategy

- (SimDeviceFramebufferService *)createMainScreenService:(NSError **)error;
- (NSDictionary<NSString *, id> *)bootOptions;

@end

@implementation FBSimulatorBootStrategy_Direct

- (FBSimulatorConnection *)performBootWithError:(NSError **)error
{
  // Create the Framebuffer
  NSError *innerError = nil;
  SimDeviceFramebufferService *mainScreenService = [self createMainScreenService:&innerError];
  if (!mainScreenService) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }
  FBFramebuffer *framebuffer = [FBFramebuffer withFramebufferService:mainScreenService configuration:self.configuration simulator:self.simulator];

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

- (SimDeviceFramebufferService *)createMainScreenService:(NSError **)error
{
  // If you're curious about where the knowledege for these parts of the CoreSimulator.framework comes from, take a look at:
  // $DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/Library/CoreSimulator/Profiles/Runtimes/iOS [VERSION].simruntime/Contents/Resources/profile.plist
  // as well as the dissasembly for CoreSimulator.framework, SimulatorKit.Framework & the Simulator.app Executable.
  //
  // Creating the Framebuffer with the 'mainScreen' constructor will return a 'PurpleFBServer' and attach it to the '_registeredServices' ivar.
  // This is the Framebuffer for the Simulator's main screen, which is distinct from 'PurpleFBTVOut' and 'Stark' Framebuffers for External Displays and CarPlay.
  //
  // -[SimDevice portForServiceNamed:error:] is gone in Xcode 8 Beta 5.
  NSError *innerError = nil;
  NSPort *purpleServerPort = [self.simulator.device portForServiceNamed:@"PurpleFBServer" error:&innerError];
  if (!purpleServerPort) {
    return [[[FBSimulatorError
      describeFormat:@"Could not find the 'PurpleFBServer' Port for %@", self.simulator.device]
      causedBy:innerError]
      fail:error];
  }

  // Setup the scale for the framebuffer service.
  CGSize size = self.simulator.device.deviceType.mainScreenSize;
  CGSize scaledSize = [self.configuration scaleSize:size];

  // Create the service
  SimDeviceFramebufferService *framebufferService = [NSClassFromString(@"SimDeviceFramebufferService")
    framebufferServiceWithPort:purpleServerPort
    deviceDimensions:size
    scaledDimensions:scaledSize
    error:&innerError];

  if (!framebufferService) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to create the Main Screen Framebuffer for device %@", self.simulator.device]
      causedBy:innerError]
      fail:error];
  }

  return framebufferService;
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

- (SimDeviceFramebufferService *)createMainScreenService:(NSError **)error
{
  NSError *innerError = nil;
  SimDeviceFramebufferService *service = [NSClassFromString(@"SimDeviceFramebufferService")
    mainScreenFramebufferServiceForDevice:self.simulator.device
    error:&innerError];
  if (!service) {
    return [[[FBSimulatorError
      describe:@"Failed to create Main Screen Service for Device"]
      causedBy:innerError]
      fail:error];
  }
  return service;
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
  id<FBTask> task = [[[[[FBTaskExecutor.sharedInstance
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
  NSURL *applicationURL = [NSURL fileURLWithPath:FBApplicationDescriptor .xcodeSimulator.path];
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

+ (instancetype)withConfiguration:(FBSimulatorLaunchConfiguration *)configuration simulator:(FBSimulator *)simulator
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

- (instancetype)initWithConfiguration:(FBSimulatorLaunchConfiguration *)configuration simulator:(FBSimulator *)simulator
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
  if (![self launchdSimWithAllRequiredProcesses:&innerError]) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }

  // Start Listening to Framebuffer events if one exists.
  [connection.framebuffer startListeningInBackground];

  // Broadcast the availability of the new bridge.
  [self.simulator.eventSink connectionDidConnect:connection];

  return YES;
}

- (FBSimulatorConnection *)performBootWithError:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (FBProcessInfo *)launchdSimWithAllRequiredProcesses:(NSError **)error
{
  FBProcessFetcher *processFetcher = self.simulator.processFetcher;
  FBProcessInfo *launchdProcess = [processFetcher launchdProcessForSimDevice:self.simulator.device];
  if (!launchdProcess) {
    return [[[FBSimulatorError
      describe:@"Could not obtain process info for launchd_sim process"]
      inSimulator:self.simulator]
      fail:error];
  }
  [self.simulator.eventSink simulatorDidLaunch:launchdProcess];

  // Waitng for all required services to start
  NSSet<NSString *> *requiredServiceNames = self.simulator.requiredLaunchdServicesToVerifyBooted;
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

@end
