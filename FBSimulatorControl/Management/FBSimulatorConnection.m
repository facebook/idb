/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorConnection.h"

#import <Cocoa/Cocoa.h>

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceType.h>

#import <SimulatorBridge/SimulatorBridge-Protocol.h>
#import <SimulatorBridge/SimulatorBridge.h>

#import <SimulatorKit/SimDeviceFramebufferService.h>

#import "FBFramebuffer.h"
#import "FBFramebufferConfiguration.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorHID.h"
#import "FBSimulatorBootConfiguration+Helpers.h"
#import "FBSimulatorBootConfiguration.h"
#import "FBSimulatorProcessFetcher.h"
#import "FBFramebufferConnectStrategy.h"

@interface FBSimulatorConnection ()

@property (nonatomic, weak, readonly) FBSimulator *simulator;
@property (nonatomic, strong, readonly) dispatch_group_t teardownGroup;

@property (nonatomic, strong, readwrite, nullable) FBFramebuffer *framebuffer;
@property (nonatomic, strong, readwrite, nullable) FBSimulatorHID *hid;
@property (nonatomic, strong, readwrite, nullable) FBSimulatorBridge *bridge;

@end

@implementation FBSimulatorConnection

#pragma mark Initializers

- (instancetype)initWithSimulator:(FBSimulator *)simulator framebuffer:(nullable FBFramebuffer *)framebuffer hid:(nullable FBSimulatorHID *)hid
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _simulator = simulator;
  _teardownGroup = dispatch_group_create();

  _framebuffer = framebuffer;
  _hid = hid;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Bridge: Framebuffer (%@) | HID %@ | %@",
    self.framebuffer.description,
    self.hid,
    self.bridge
  ];
}

#pragma mark FBJSONSerializable Implementation

- (id)jsonSerializableRepresentation
{
  return @{
    @"framebuffer" : self.framebuffer.jsonSerializableRepresentation ?: NSNull.null,
    @"hid" : self.hid.jsonSerializableRepresentation ?: NSNull.null,
    @"bridge" : self.bridge.jsonSerializableRepresentation ?: NSNull.null,
  };
}

#pragma mark Lifecycle

- (nullable FBSimulatorBridge *)connectToBridge:(NSError **)error
{
  if (self.bridge) {
    return self.bridge;
  }

  self.bridge = [FBSimulatorBridge bridgeForSimulator:self.simulator error:error];
  return self.bridge;
}

- (nullable FBFramebuffer *)connectToFramebuffer:(NSError **)error
{
  if (self.framebuffer) {
    return self.framebuffer;
  }

  self.framebuffer = [[FBFramebufferConnectStrategy
    strategyWithConfiguration:[FBFramebufferConfiguration.defaultConfiguration inSimulator:self.simulator]]
    connect:self.simulator error:error];
  return self.framebuffer;
}

- (nullable FBSimulatorHID *)connectToHID:(NSError **)error
{
  if (self.hid) {
    return [self.hid connect:error] ? self.hid : nil;
  }
  return [[FBSimulatorError
    describe:@"Could not connect to HID, it must be provided on launch"]
    fail:error];
}

- (BOOL)terminateWithTimeout:(NSTimeInterval)timeout
{
  NSParameterAssert(NSThread.currentThread.isMainThread);

  // Tear Down the Framebuffer
  [self.framebuffer teardownWithGroup:self.teardownGroup];

  // Disconnect the HID
  [self.hid disconnect];

  // Close the connection with the SimulatorBridge and nullify
  [self.bridge disconnect];

  // Don't wait if there's no timeout
  if (timeout <= 0) {
    return YES;
  }

  int64_t timeoutInt = ((int64_t) timeout) * ((int64_t) NSEC_PER_SEC);
  BOOL result = dispatch_group_wait(self.teardownGroup, dispatch_time(DISPATCH_TIME_NOW, timeoutInt)) == 0l;

  // Clean up resources and notify.
  self.framebuffer = nil;
  self.hid = nil;
  self.bridge = nil;
  [self.simulator.eventSink connectionDidDisconnect:self expected:YES];

  return result;
}

@end
