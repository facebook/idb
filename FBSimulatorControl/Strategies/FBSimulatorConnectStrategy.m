/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorConnectStrategy.h"

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
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorLaunchConfiguration+Helpers.h"
#import "FBSimulatorLaunchConfiguration.h"

@interface FBSimulatorConnectStrategy ()

@property (nonatomic, strong, readonly, nonnull) FBSimulator *simulator;
@property (nonatomic, strong, readonly, nullable) FBFramebuffer *framebuffer;
@property (nonatomic, assign, readonly) mach_port_t hidPort;

@end

@implementation FBSimulatorConnectStrategy

+ (instancetype)withSimulator:(FBSimulator *)simulator framebuffer:(FBFramebuffer *)framebuffer hidPort:(mach_port_t)hidPort;
{
  return [[self alloc] initWithSimulator:simulator framebuffer:framebuffer hidPort:hidPort];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator framebuffer:(FBFramebuffer *)framebuffer hidPort:(mach_port_t)hidPort
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _framebuffer = framebuffer;
  _hidPort = hidPort;

  return self;
}

- (FBSimulatorBridge *)connect:(NSError **)error
{
  // Return early if the bridge exists.
  if (self.simulator.bridge) {
    return self.simulator.bridge;
  }

  // Connect to the expected-to-be-running CoreSimulatorBridge running inside the Simulator.
  // This mimics the behaviour of Simulator.app, which just looks up the service then connects to the distant object over a Remote Object connection.
  NSError *innerError = nil;
  mach_port_t port = [self.simulator.device lookup:@"com.apple.iphonesimulator.bridge" error:&innerError];
  if (port == 0) {
    return [[[FBSimulatorError
      describe:@"Could not lookup mach port for 'com.apple.iphonesimulator.bridge'"]
      inSimulator:self.simulator]
      fail:error];
  }
  NSPort *machPort = [NSMachPort portWithMachPort:port];
  NSConnection *connection = [NSConnection connectionWithReceivePort:nil sendPort:machPort];
  NSDistantObject *distantObject = [connection rootProxy];
  if (![distantObject respondsToSelector:@selector(setLocationScenarioWithPath:)]) {
    return [[[FBSimulatorError
      describeFormat:@"Distant Object '%@' for 'com.apple.iphonesimulator.bridge' at port %d isn't a SimulatorBridge", distantObject, port]
      inSimulator:self.simulator]
      fail:error];
  }

  // Start Listening to Framebuffer events if one exists.
  [self.framebuffer startListeningInBackground];

  // Load Accessibility, return early if this fails
  id simulatorBridge = (id) distantObject;
  [simulatorBridge enableAccessibility];
  if (![simulatorBridge accessibilityEnabled]) {
    return [[[FBSimulatorError
      describeFormat:@"Could not enable accessibility for bridge '%@'", simulatorBridge]
      inSimulator:self.simulator]
      fail:error];
  }

  // Create the bridge.
  FBSimulatorBridge *bridge = [[FBSimulatorBridge alloc] initWithFramebuffer:self.framebuffer hidPort:self.hidPort bridge:simulatorBridge eventSink:self.simulator.eventSink];
  // Set the Location to a default location, when launched directly.
  // This is effectively done by Simulator.app by a NSUserDefault with for the 'LocationMode', even when the location is 'None'.
  // If the Location is set on the Simulator, then CLLocationManager will behave in a consistent manner inside launched Applications.
  if (self.framebuffer) {
    [bridge setLocationWithLatitude:37.485023 longitude:-122.147911];
  }

  // Broadcast the availability of the new bridge.
  [self.simulator.eventSink bridgeDidConnect:bridge];
  return bridge;
}

@end
