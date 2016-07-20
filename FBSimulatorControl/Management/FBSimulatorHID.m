/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorHID.h"

#import <CoreSimulator/SimDevice.h>

#import <mach/mach_port.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"

@interface FBSimulatorHID ()

@property (nonatomic, assign, readwrite) mach_port_t port;

@end

@implementation FBSimulatorHID

+ (instancetype)hidPortForSimulator:(FBSimulator *)simulator error:(NSError **)error
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
      fail:error];
  }
  result = mach_port_insert_right(machTask, hidPort, hidPort, MACH_MSG_TYPE_MAKE_SEND);
  if (result != KERN_SUCCESS) {
    return [[FBSimulatorError
      describeFormat:@"Failed to 'insert_right' the mach port with code %d", result]
      fail:error];
  }
  // Then register it as the 'IndigoHIDRegistrationPort'
  if (![simulator.device registerPort:hidPort service:@"IndigoHIDRegistrationPort" error:&innerError]) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to register %d as the IndigoHIDRegistrationPort", hidPort]
      causedBy:innerError]
      fail:error];
  }

  return [[FBSimulatorHID alloc] initWithPort:hidPort];
}

- (instancetype)initWithPort:(mach_port_t)port
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _port = port;

  return self;
}

- (void)disconnect
{
  if (self.port == 0) {
    return;
  }
  mach_port_destroy(mach_task_self(), self.port);
  self.port = 0;
}

- (void)dealloc
{
  [self disconnect];
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  if (self.port == 0) {
    return @"Indigo HID Port: Not Connected";
  }
  return [NSString stringWithFormat:@"Indigo HID Port: %u", self.port];
}

- (NSString *)shortDescription
{
  return self.description;
}

- (NSString *)debugDescription
{
  return self.description;
}

#pragma mark FBJSONSerializable

- (id)jsonSerializableRepresentation
{
  return @{
    @"hid_port" : (self.port == 0 ? NSNull.null : @(self.port)),
  };
}

@end
