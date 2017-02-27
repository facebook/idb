/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBFramebufferConnectStrategy.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDevice+Removed.h>
#import <CoreSimulator/SimDeviceType.h>

#import <SimulatorKit/SimDeviceFramebufferService.h>
#import <SimulatorKit/SimDeviceFramebufferService+Removed.h>

#import <objc/runtime.h>

#import "FBFramebuffer.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorConnection.h"
#import "FBSimulatorError.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBFramebufferConfiguration.h"

@interface FBFramebufferConnectStrategy ()

@property (nonatomic, strong, readonly) FBFramebufferConfiguration *configuration;

@end

@interface FBFramebufferConnectStrategy_IOPortClient : FBFramebufferConnectStrategy
@end

@interface FBFramebufferConnectStrategy_FramebufferService : FBFramebufferConnectStrategy

- (nullable SimDeviceFramebufferService *)createMainScreenService:(FBSimulator *)simulator error:(NSError **)error;

@end

@interface FBFramebufferConnectStrategy_Xcode7 : FBFramebufferConnectStrategy_FramebufferService
@end

@interface FBFramebufferConnectStrategy_Xcode8 : FBFramebufferConnectStrategy_FramebufferService
@end

@implementation FBFramebufferConnectStrategy

+ (instancetype)strategyWithConfiguration:(FBFramebufferConfiguration *)configuration
{
  if (objc_getClass("SimDeviceIOClient")) {
    return [[FBFramebufferConnectStrategy_IOPortClient alloc] initWithConfiguration:configuration];
  }
  if (FBControlCoreGlobalConfiguration.isXcode8OrGreater) {
    return [[FBFramebufferConnectStrategy_Xcode8 alloc] initWithConfiguration:configuration];
  }
  return [[FBFramebufferConnectStrategy_Xcode7 alloc] initWithConfiguration:configuration];
}

- (instancetype)initWithConfiguration:(FBFramebufferConfiguration *)configuration
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;

  return self;
}

- (nullable FBFramebuffer *)connect:(FBSimulator *)simulator error:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

@end

@implementation FBFramebufferConnectStrategy_IOPortClient

- (nullable FBFramebuffer *)connect:(FBSimulator *)simulator error:(NSError **)error
{
  return [[FBFramebuffer
    withIOClient:(SimDeviceIOClient *)simulator.device.io configuration:self.configuration simulator:simulator]
    startListeningInBackground];
}

@end

@implementation FBFramebufferConnectStrategy_FramebufferService

- (nullable FBFramebuffer *)connect:(FBSimulator *)simulator error:(NSError **)error
{
  NSError *innerError = nil;
  if (![self meetsPreconditionsForConnectingToSimulator:simulator error:&innerError]) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  SimDeviceFramebufferService *mainScreenService = [self createMainScreenService:simulator error:&innerError];
  if (!mainScreenService) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }
  return [[FBFramebuffer
    withFramebufferService:mainScreenService configuration:self.configuration simulator:simulator]
    startListeningInBackground];
}

- (BOOL)meetsPreconditionsForConnectingToSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return NO;
}

- (nullable SimDeviceFramebufferService *)createMainScreenService:(FBSimulator *)simulator error:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

@end

@implementation FBFramebufferConnectStrategy_Xcode7

- (BOOL)meetsPreconditionsForConnectingToSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  if (simulator.state != FBSimulatorStateShutdown) {
    return [[FBSimulatorError
      describeFormat:@"Cannot connect Framebuffer unless shutdown, actual state %@", [FBSimulator stateStringFromSimulatorState:simulator.state]]
      failBool:error];
  }
  return YES;
}

- (nullable SimDeviceFramebufferService *)createMainScreenService:(FBSimulator *)simulator error:(NSError **)error
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
  NSPort *purpleServerPort = [simulator.device portForServiceNamed:@"PurpleFBServer" error:&innerError];
  if (!purpleServerPort) {
    return [[[FBSimulatorError
      describeFormat:@"Could not find the 'PurpleFBServer' Port for %@", simulator.device]
      causedBy:innerError]
      fail:error];
  }

  // Setup the scale for the framebuffer service.
  CGSize size = simulator.device.deviceType.mainScreenSize;
  CGSize scaledSize = [self.configuration scaleSize:size];

  // Create the service
  SimDeviceFramebufferService *framebufferService = [objc_lookUpClass("SimDeviceFramebufferService")
    framebufferServiceWithPort:purpleServerPort
    deviceDimensions:size
    scaledDimensions:scaledSize
    error:&innerError];

  if (!framebufferService) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to create the Main Screen Framebuffer for device %@", simulator.device]
      causedBy:innerError]
      fail:error];
  }

  return framebufferService;
}

@end

@implementation FBFramebufferConnectStrategy_Xcode8

- (BOOL)meetsPreconditionsForConnectingToSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  if (simulator.state != FBSimulatorStateShutdown && simulator.state != FBSimulatorStateBooted) {
    return [[FBSimulatorError
      describeFormat:@"Cannot connect Framebuffer unless shutdown or booted, actual state %@", [FBSimulator stateStringFromSimulatorState:simulator.state]]
      failBool:error];
  }
  return YES;
}

- (nullable SimDeviceFramebufferService *)createMainScreenService:(FBSimulator *)simulator error:(NSError **)error
{
  NSError *innerError = nil;
  SimDeviceFramebufferService *service = [objc_lookUpClass("SimDeviceFramebufferService")
    mainScreenFramebufferServiceForDevice:simulator.device
    error:&innerError];
  if (!service) {
    return [[[FBSimulatorError
      describe:@"Failed to create Main Screen Service for Device"]
      causedBy:innerError]
      fail:error];
  }
  return service;
}

@end
