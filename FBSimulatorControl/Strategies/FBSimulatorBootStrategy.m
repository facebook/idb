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
#import <CoreSimulator/SimDeviceType.h>

#import <SimulatorBridge/SimulatorBridge-Protocol.h>
#import <SimulatorBridge/SimulatorBridge.h>

#import <SimulatorKit/SimDeviceFramebufferService.h>

#import "FBFramebuffer.h"
#import "FBProcessFetcher+Simulators.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorConnectStrategy.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorLaunchConfiguration+Helpers.h"
#import "FBSimulatorLaunchConfiguration.h"

@interface FBSimulatorBootStrategy ()

@property (nonatomic, strong, readonly, nonnull) FBSimulatorLaunchConfiguration *configuration;
@property (nonatomic, strong, readonly, nonnull) FBSimulator *simulator;

- (BOOL)performBoot:(NSError **)error framebufferServiceOut:(SimDeviceFramebufferService **)framebufferServiceOut hidPortOut:(mach_port_t *)hidPortOut;

@end

@interface FBSimulatorBootStrategy_Direct : FBSimulatorBootStrategy

@end

@implementation FBSimulatorBootStrategy_Direct

- (BOOL)performBoot:(NSError **)error framebufferServiceOut:(SimDeviceFramebufferService **)framebufferServiceOut hidPortOut:(mach_port_t *)hidPortOut
{
  // Create the Framebuffer
  NSError *innerError = nil;
  SimDeviceFramebufferService *framebufferService = [self createFramebufferService:&innerError];
  if (!framebufferService) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }

  // Create the HID Port
  mach_port_t hidPort = [self createIndigoHIDRegistrationPort:&innerError];
  if (hidPort == 0) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }

  // The 'register-head-services' option will attach the existing 'frameBufferService' when the Simulator is booted.
  // Simulator.app behaves similarly, except we can't peek at the Framebuffer as it is in a protected process since Xcode 7.
  // Prior to Xcode 6 it was possible to shim into the Simulator process but codesigning now prevents this https://gist.github.com/lawrencelomax/27bdc4e8a433a601008f
  NSDictionary *options = @{
    @"register-head-services" : @YES
  };

  // Booting is simpler than the Simulator.app launch process since the caller calls CoreSimulator Framework directly.
  // Just pass in the options to ensure that the framebuffer service is registered when the Simulator is booted.
  if (![self.simulator.device bootWithOptions:options error:&innerError]) {
    return [[[[FBSimulatorError
      describeFormat:@"Failed to boot Simulator with options %@", options]
      inSimulator:self.simulator]
      causedBy:innerError]
      failBool:error];
  }

  *framebufferServiceOut = framebufferService;
  *hidPortOut = hidPort;
  return YES;
}

- (SimDeviceFramebufferService *)createFramebufferService:(NSError **)error
{
  // If you're curious about where the knowledege for these parts of the CoreSimulator.framework comes from, take a look at:
  // $DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/Library/CoreSimulator/Profiles/Runtimes/iOS [VERSION].simruntime/Contents/Resources/profile.plist
  // as well as the dissasembly for CoreSimulator.framework, SimulatorKit.Framework & the Simulator.app Executable.

  // Creating the Framebuffer with the 'mainScreen' constructor will return a 'PurpleFBServer' and attach it to the '_registeredServices' ivar.
  // This is the Framebuffer for the Simulator's main screen, which is distinct from 'PurpleFBTVOut' and 'Stark' Framebuffers for External Displays and CarPlay.
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

- (mach_port_t)createIndigoHIDRegistrationPort:(NSError **)error
{
  // As with the 'PurpleFBServer', a 'IndigoHIDRegistrationPort' is needed in order for the synthesis of touch events to work appropriately.
  // If this is not set you will see the following logger message in the System log upon booting the simulator
  // 'backboardd[10667]: BKHID: Unable to open Indigo HID system'
  // The dissasembly for backboardd shows that this will happen when the call to 'IndigoHIDSystemSpawnLoopback' fails.
  // Simulator.app creates a Mach Port for the 'IndigoHIDRegistrationPort' and therefore succeeds in the above call.
  // As with 'PurpleFBServer' this can be registered with 'register-head-services'
  // The first step is to create the mach port
  NSError *innerError = nil;
  mach_port_t hidPort = 0;
  mach_port_t machTask = mach_task_self();
  kern_return_t result = mach_port_allocate(machTask, MACH_PORT_RIGHT_RECEIVE, &hidPort);
  if (result != KERN_SUCCESS) {
    return [[FBSimulatorError
      describeFormat:@"Failed to create a Mach Port for IndigoHIDRegistrationPort with code %d", result]
      failUInt:error];
  }
  result = mach_port_insert_right(machTask, hidPort, hidPort, MACH_MSG_TYPE_MAKE_SEND);
  if (result != KERN_SUCCESS) {
    return [[FBSimulatorError
      describeFormat:@"Failed to 'insert_right' the mach port with code %d", result]
      failUInt:error];
  }
  // Then register it as the 'IndigoHIDRegistrationPort'
  if (![self.simulator.device registerPort:hidPort service:@"IndigoHIDRegistrationPort" error:&innerError]) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to register %d as the IndigoHIDRegistrationPort", hidPort]
      causedBy:innerError]
      failUInt:error];
  }

  return hidPort;
}

@end

@interface FBSimulatorBootStrategy_Subprocess : FBSimulatorBootStrategy

- (BOOL)launchSimulatorProcessWithArguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment error:(NSError **)error;

@end

@implementation FBSimulatorBootStrategy_Subprocess

- (BOOL)performBoot:(NSError **)error framebufferServiceOut:(SimDeviceFramebufferService **)framebufferServiceOut hidPortOut:(mach_port_t *)hidPortOut
{
  // Fetch the Boot Arguments & Environment
  NSError *innerError = nil;
  NSArray *arguments = [self.configuration xcodeSimulatorApplicationArgumentsForSimulator:self.simulator error:&innerError];
  if (!arguments) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to create boot args for Configuration %@", self.configuration]
      causedBy:innerError]
      failBool:error];
  }
  // Add the UDID marker to the subprocess environment, so that it can be queried in any process.
  NSDictionary *environment = @{
    FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID : self.simulator.udid
  };

  // Launch the Simulator.app Process.
  if (![self launchSimulatorProcessWithArguments:arguments environment:environment error:&innerError]) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }

  // Expect the state of the simulator to be updated.
  BOOL didBoot = [self.simulator waitOnState:FBSimulatorStateBooted];
  if (!didBoot) {
    return [[[FBSimulatorError
      describeFormat:@"Timed out waiting for device to be Booted, got %@", self.simulator.device.stateString]
      inSimulator:self.simulator]
      failBool:error];
  }

  // Expect the launch info for the process to exist.
  FBProcessInfo *containerApplication = [self.simulator.processFetcher simulatorApplicationProcessForSimDevice:self.simulator.device];
  if (!containerApplication) {
    return [[[FBSimulatorError
      describe:@"Could not obtain process info for container application"]
      inSimulator:self.simulator]
      failBool:error];
  }
  [self.simulator.eventSink containerApplicationDidLaunch:containerApplication];

  return YES;
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
    withLaunchPath:FBSimulatorApplication.xcodeSimulator.binary.path]
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
  NSURL *applicationURL = [NSURL fileURLWithPath:FBSimulatorApplication.xcodeSimulator.path];
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
    return [[FBSimulatorBootStrategy_Direct alloc] initWithConfiguration:configuration simulator:simulator];
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

  NSError *innerError = nil;
  mach_port_t hidPort = 0;
  SimDeviceFramebufferService *framebufferService = nil;

  // Fail if there was an error.
  if (![self performBoot:&innerError framebufferServiceOut:&framebufferService hidPortOut:&hidPort]) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }

  // Connect the Bridge.
  FBFramebuffer *framebuffer = framebufferService ? [FBFramebuffer withFramebufferService:framebufferService configuration:self.configuration simulator:self.simulator] : nil;
  FBSimulatorBridge *bridge = self.configuration.shouldConnectBridge ? [[FBSimulatorConnectStrategy withSimulator:self.simulator framebuffer:framebuffer hidPort:hidPort] connect:&innerError] : nil;
  if (self.configuration.shouldConnectBridge && !bridge) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }

  // Expect the launchd_sim process to be updated.
  if (![self launchdSimWithAllRequiredProcesses:&innerError]) {
    return [FBSimulatorError failBoolWithError:innerError errorOut:error];
  }

  return YES;
}

- (BOOL)performBoot:(NSError **)error framebufferServiceOut:(SimDeviceFramebufferService **)framebufferServiceOut hidPortOut:(mach_port_t *)hidPortOut
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return NO;
}

- (FBProcessInfo *)launchdSimWithAllRequiredProcesses:(NSError **)error
{
  FBProcessFetcher *processFetcher = self.simulator.processFetcher;
  FBProcessInfo *launchdSimProcess = [processFetcher launchdSimProcessForSimDevice:self.simulator.device];
  if (!launchdSimProcess) {
    return [[[FBSimulatorError
      describe:@"Could not obtain process info for launchd_sim process"]
      inSimulator:self.simulator]
      fail:error];
  }
  [self.simulator.eventSink simulatorDidLaunch:launchdSimProcess];

  // Waitng for all required processes to start
  NSSet *requiredProcessNames = self.simulator.requiredProcessNamesToVerifyBooted;
  BOOL didStartAllRequiredProcesses = [NSRunLoop.mainRunLoop spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.slowTimeout untilTrue:^ BOOL {
    NSSet *runningProcessNames = [NSSet setWithArray:[[processFetcher subprocessesOf:launchdSimProcess.processIdentifier] valueForKey:@"processName"]];
    return [requiredProcessNames isSubsetOfSet:runningProcessNames];
  }];
  if (!didStartAllRequiredProcesses) {
    return [[[FBSimulatorError
      describeFormat:@"Timed out waiting for all required processes %@ to start", [FBCollectionInformation oneLineDescriptionFromArray:requiredProcessNames.allObjects]]
      inSimulator:self.simulator]
      fail:error];
  }

  return launchdSimProcess;
}

@end
