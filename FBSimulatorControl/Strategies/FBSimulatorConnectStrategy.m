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

#import <SimulatorKit/SimDeviceFramebufferService.h>

#import <FBControlCore/FBControlCore.h>

#import "FBFramebuffer.h"
#import "FBProcessFetcher+Simulators.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorConnection.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorLaunchConfiguration+Helpers.h"
#import "FBSimulatorLaunchConfiguration.h"

@interface FBSimulatorConnectStrategy ()

@property (nonatomic, strong, readonly, nonnull) FBSimulator *simulator;
@property (nonatomic, strong, readonly, nullable) FBFramebuffer *framebuffer;
@property (nonatomic, strong, readonly, nullable) FBSimulatorHID *hid;

@end

@implementation FBSimulatorConnectStrategy

+ (instancetype)withSimulator:(FBSimulator *)simulator framebuffer:(nullable FBFramebuffer *)framebuffer hid:(nullable FBSimulatorHID *)hid
{
  return [[self alloc] initWithSimulator:simulator framebuffer:framebuffer hid:hid];
}

- (instancetype)initWithSimulator:(FBSimulator *)simulator framebuffer:(FBFramebuffer *)framebuffer hid:(nullable FBSimulatorHID *)hid
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _framebuffer = framebuffer;
  _hid = hid;

  return self;
}

- (FBSimulatorConnection *)connect:(NSError **)error
{
  // Return early if the bridge exists.
  if (self.simulator.connection) {
    return self.simulator.connection;
  }

  // Connect to the expected-to-be-running CoreSimulatorBridge running inside the Simulator.
  // This mimics the behaviour of Simulator.app, which just looks up the service then connects to the distant object over a Remote Object connection.
  NSError *innerError = nil;
  mach_port_t bridgePort = [self.simulator.device lookup:@"com.apple.iphonesimulator.bridge" error:&innerError];
  if (bridgePort == 0) {
    return [[[FBSimulatorError
      describe:@"Could not lookup mach port for 'com.apple.iphonesimulator.bridge'"]
      inSimulator:self.simulator]
      fail:error];
  }
  NSPort *bridgeMachPort = [NSMachPort portWithMachPort:bridgePort];
  NSConnection *bridgeConnection = [NSConnection connectionWithReceivePort:nil sendPort:bridgeMachPort];
  NSDistantObject *bridgeDistantObject = [bridgeConnection rootProxy];
  FBSimulatorBridge *bridge = [FBSimulatorBridge bridgeForDistantObject:bridgeDistantObject error:&innerError];
  if (!bridge) {
    return [FBSimulatorError failWithError:innerError errorOut:error];
  }

  // Start Listening to Framebuffer events if one exists.
  [self.framebuffer startListeningInBackground];

  // Create the Connection.
  FBSimulatorConnection *connection = [[FBSimulatorConnection alloc] initWithFramebuffer:self.framebuffer hid:self.hid bridge:bridge eventSink:self.simulator.eventSink];

  // Set the Location to a default location, when launched directly.
  // This is effectively done by Simulator.app by a NSUserDefault with for the 'LocationMode', even when the location is 'None'.
  // If the Location is set on the Simulator, then CLLocationManager will behave in a consistent manner inside launched Applications.
  if (self.framebuffer) {
    [bridge setLocationWithLatitude:37.485023 longitude:-122.147911];
  }

  // Broadcast the availability of the new bridge.
  [self.simulator.eventSink connectionDidConnect:connection];
  return connection;
}

@end
