/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorBridge.h"

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
#import "FBProcessLaunchConfiguration.h"
#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorLaunchConfiguration+Helpers.h"
#import "FBSimulatorLaunchConfiguration.h"

@interface FBSimulatorBridge ()

@property (nonatomic, strong, readonly) id<FBSimulatorEventSink> eventSink;
@property (nonatomic, strong, readonly) dispatch_group_t teardownGroup;

@property (nonatomic, assign, readwrite) mach_port_t hidPort;
@property (nonatomic, strong, readwrite) SimulatorBridge *bridge;

@end

@implementation FBSimulatorBridge

#pragma mark Initializers

- (instancetype)initWithFramebuffer:(nullable FBFramebuffer *)framebuffer hidPort:(mach_port_t)hidPort bridge:(SimulatorBridge *)bridge eventSink:(id<FBSimulatorEventSink>)eventSink
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _eventSink = eventSink;
  _teardownGroup = dispatch_group_create();

  _framebuffer = framebuffer;
  _hidPort = hidPort;
  _bridge = bridge;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Bridge: Framebuffer (%@) | hid_port %d | Bridge Exists %d",
    self.framebuffer.description,
    self.hidPort,
    self.bridge != nil
  ];
}

#pragma mark FBJSONSerializable Implementation

- (id)jsonSerializableRepresentation
{
  return @{
    @"framebuffer" : self.framebuffer.jsonSerializableRepresentation ?: NSNull.null,
    @"hid_port" : @(self.hidPort),
    @"bridge_exists" : @(self.bridge != nil)
  };
}

#pragma mark Lifecycle

- (BOOL)terminateWithTimeout:(NSTimeInterval)timeout
{
  NSParameterAssert(NSThread.currentThread.isMainThread);

  // First stop the Framebuffer
  [self.framebuffer stopListeningWithTeardownGroup:self.teardownGroup];
  // Disconnect the HID Port
  if (self.hidPort != 0) {
    mach_port_destroy(mach_task_self(), self.hidPort);
    self.hidPort = 0;
  }
  // Close the connection with the SimulatorBridge and nullify
  NSDistantObject *distantObject = (NSDistantObject *) self.bridge;
  self.bridge = nil;
  [[distantObject connectionForProxy] invalidate];
  // Notify the eventSink
  [self.eventSink bridgeDidDisconnect:self expected:YES];

  // Don't wait if there's no timeout
  if (timeout <= 0) {
    return YES;
  }

  int64_t timeoutInt = ((int64_t) timeout) * ((int64_t) NSEC_PER_SEC);
  long status = dispatch_group_wait(self.teardownGroup, dispatch_time(DISPATCH_TIME_NOW, timeoutInt));
  return status == 0l;
}

#pragma mark Interacting with the Simulator

- (void)setLocationWithLatitude:(double)latitude longitude:(double)longitude
{
  [self.bridge setLocationWithLatitude:latitude andLongitude:longitude];
}

- (BOOL)tapX:(double)x y:(double)y error:(NSError **)error
{
  NSDictionary *elementDictionary = [self.bridge accessibilityElementForPoint:x andY:y displayId:0];
  if (!elementDictionary) {
    return [[FBSimulatorError
      describeFormat:@"Could not find element at (%f, %f)", x, y]
      failBool:error];
  }
  if (![self.bridge performPressAction:elementDictionary]) {
    return [[FBSimulatorError
      describeFormat:@"Could not Press Element with description %@", elementDictionary]
      failBool:error];
  }
  return YES;
}

- (pid_t)launch:(FBApplicationLaunchConfiguration *)configuration stdOutPath:(NSString *)stdOutPath stdErrPath:(NSString *)stdErrPath error:(NSError **)error
{
  NSDictionary<NSString *, id> *result = [self.bridge
   bksLaunchApplicationWithBundleId:configuration.bundleID
   arguments:configuration.arguments
   environment:configuration.environment
   standardOutPipe:stdOutPath
   standardErrorPipe:stdErrPath
   options:@{}];

  if ([result[@"result"] integerValue] != 0) {
    [[FBSimulatorError describeFormat:@"Non-Zero result %@", result] fail:error];
    return -1;
  }

  pid_t processIdentifier = [result[@"pid"] intValue];
  if (processIdentifier <= 0) {
    [[FBSimulatorError describeFormat:@"No Pid Value in result %@", result] fail:error];
    return -1;
  }

  return processIdentifier;
}

@end
