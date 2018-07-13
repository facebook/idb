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

#import <objc/runtime.h>

#import "FBFramebuffer.h"
#import "FBFramebufferConfiguration.h"
#import "FBFramebufferSurface.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorConnection.h"
#import "FBSimulatorError.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"

@interface FBFramebufferConnectStrategy ()

@property (nonatomic, strong, readonly) FBFramebufferConfiguration *configuration;

@end

@interface FBFramebufferConnectStrategy_IOPortClient : FBFramebufferConnectStrategy
@end

@interface FBFramebufferConnectStrategy_FramebufferService : FBFramebufferConnectStrategy

- (nullable SimDeviceFramebufferService *)createMainScreenService:(FBSimulator *)simulator error:(NSError **)error;

@end

@interface FBFramebufferConnectStrategy_Xcode8 : FBFramebufferConnectStrategy_FramebufferService
@end

@implementation FBFramebufferConnectStrategy

+ (instancetype)strategyWithConfiguration:(FBFramebufferConfiguration *)configuration
{
  if (objc_getClass("SimDeviceIOClient")) {
    return [[FBFramebufferConnectStrategy_IOPortClient alloc] initWithConfiguration:configuration];
  }
  return [[FBFramebufferConnectStrategy_Xcode8 alloc] initWithConfiguration:configuration];
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

- (FBFuture<FBFramebuffer *> *)connect:(FBSimulator *)simulator
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

@end

@implementation FBFramebufferConnectStrategy_IOPortClient

- (FBFuture<FBFramebuffer *> *)connect:(FBSimulator *)simulator
{
  NSError *error = nil;
  FBFramebufferSurface *renderable = [FBFramebufferSurface mainScreenSurfaceForClient:(SimDeviceIOClient *)simulator.device.io logger:simulator.logger error:&error];
  if (!renderable) {
    return [FBFuture futureWithError:error];
  }
  FBFramebuffer *framebuffer = [FBFramebuffer framebufferWithRenderable:renderable configuration:self.configuration simulator:simulator];
  return [FBFuture futureWithResult:framebuffer];
}

@end

@implementation FBFramebufferConnectStrategy_FramebufferService

- (FBFuture<FBFramebuffer *> *)connect:(FBSimulator *)simulator
{
  NSError *error = nil;
  if (![self meetsPreconditionsForConnectingToSimulator:simulator error:&error]) {
    return [FBFuture futureWithError:error];
  }

  SimDeviceFramebufferService *mainScreenService = [self createMainScreenService:simulator error:&error];
  if (!mainScreenService) {
    return [FBFuture futureWithError:error];
  }
  FBFramebuffer *framebuffer = [FBFramebuffer framebufferWithService:mainScreenService configuration:self.configuration simulator:simulator];
  return [FBFuture futureWithResult:framebuffer];
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

@implementation FBFramebufferConnectStrategy_Xcode8

- (BOOL)meetsPreconditionsForConnectingToSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  if (simulator.state != FBSimulatorStateShutdown && simulator.state != FBSimulatorStateBooted) {
    return [[FBSimulatorError
      describeFormat:@"Cannot connect Framebuffer unless shutdown or booted, actual state %@", simulator.stateString]
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
