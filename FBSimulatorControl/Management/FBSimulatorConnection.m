/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorConnection.h"

#import <Foundation/Foundation.h>

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceType.h>

#import <SimulatorBridge/SimulatorBridge-Protocol.h>
#import <SimulatorBridge/SimulatorBridge.h>

#import "FBFramebuffer.h"
#import "FBFramebufferConfiguration.h"
#import "FBSimulator+Private.h"
#import "FBSimulator.h"
#import "FBSimulatorBridge.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorHID.h"
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

- (instancetype)initWithSimulator:(FBSimulator *)simulator framebuffer:(FBFramebuffer *)framebuffer hid:(FBSimulatorHID *)hid
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

- (FBFuture<FBSimulatorBridge *> *)connectToBridge
{
  if (self.bridge) {
    return [FBFuture futureWithResult:self.bridge];
  }

  return [[FBSimulatorBridge
    bridgeForSimulator:self.simulator]
    onQueue:self.simulator.workQueue map:^(FBSimulatorBridge *bridge) {
      self.bridge = bridge;
      return bridge;
    }];
}

- (FBFuture<FBFramebuffer *> *)connectToFramebuffer
{
  if (self.framebuffer) {
    return [FBFuture futureWithResult:self.framebuffer];
  }

  return [[[FBFramebufferConnectStrategy
    strategyWithConfiguration:[FBFramebufferConfiguration.defaultConfiguration inSimulator:self.simulator]]
    connect:self.simulator]
    onQueue:self.simulator.workQueue map:^(FBFramebuffer *framebuffer) {
      self.framebuffer = framebuffer;
      return framebuffer;
    }];
}

- (FBFuture<FBSimulatorHID *> *)connectToHID
{
  if (self.hid) {
    return [FBFuture futureWithResult:self.hid];
  }
  return [[FBSimulatorHID
    hidForSimulator:self.simulator]
    onQueue:self.simulator.workQueue map:^(FBSimulatorHID *hid) {
      self.hid = hid;
      return hid;
    }];
}

- (FBFuture<NSNull *> *)terminate
{
  NSParameterAssert(NSThread.currentThread.isMainThread);

  // Disconnect the HID
  [self.hid disconnect];

  // Close the connection with the SimulatorBridge and nullify
  [self.bridge disconnect];

  // Nullify
  self.framebuffer = nil;
  self.hid = nil;
  self.bridge = nil;
  [self.simulator.eventSink connectionDidDisconnect:self expected:YES];

  return FBFuture.empty;
}

@end
