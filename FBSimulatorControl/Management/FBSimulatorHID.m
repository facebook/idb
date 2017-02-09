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
#import <SimulatorApp/Indigo.h>

#import <mach/mach.h>
#import <mach/mach_time.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"

@interface FBSimulatorHID ()

@property (nonatomic, assign, readwrite) mach_port_t registrationPort;
@property (nonatomic, assign, readwrite) mach_port_t replyPort;

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
  mach_port_t registrationPort = 0;
  mach_port_t machTask = mach_task_self();
  kern_return_t result = mach_port_allocate(machTask, MACH_PORT_RIGHT_RECEIVE, &registrationPort);
  if (result != KERN_SUCCESS) {
    return [[FBSimulatorError
      describeFormat:@"Failed to create a Mach Port for IndigoHIDRegistrationPort with code %d", result]
      fail:error];
  }
  result = mach_port_insert_right(machTask, registrationPort, registrationPort, MACH_MSG_TYPE_MAKE_SEND);
  if (result != KERN_SUCCESS) {
    return [[FBSimulatorError
      describeFormat:@"Failed to 'insert_right' the mach port with code %d", result]
      fail:error];
  }
  // Then register it as the 'IndigoHIDRegistrationPort'
  if (![simulator.device registerPort:registrationPort service:@"IndigoHIDRegistrationPort" error:&innerError]) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to register %d as the IndigoHIDRegistrationPort", registrationPort]
      causedBy:innerError]
      fail:error];
  }

  return [[FBSimulatorHID alloc] initWithRegistrationPort:registrationPort];
}

- (instancetype)initWithRegistrationPort:(mach_port_t)registrationPort
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _registrationPort = registrationPort;
  _replyPort = 0;

  return self;
}

- (BOOL)connect:(NSError **)error
{
  if (self.registrationPort == 0) {
    return [[FBSimulatorError
      describe:@"Cannot connect when there is no registration port"]
      failBool:error];
  }
  if (self.replyPort != 0) {
    return YES;
  }

  // Attempt to perform the handshake.
  mach_msg_size_t size = 0x400;
  mach_msg_timeout_t timeout = ((unsigned int) FBControlCoreGlobalConfiguration.regularTimeout) * 1000;
  mach_msg_header_t *handshakeHeader = calloc(1, sizeof(mach_msg_header_t));
  handshakeHeader->msgh_bits = 0;
  handshakeHeader->msgh_size = size;
  handshakeHeader->msgh_remote_port = 0;
  handshakeHeader->msgh_local_port = self.registrationPort;

  kern_return_t result = mach_msg(handshakeHeader, MACH_RCV_LARGE | MACH_RCV_MSG, 0x0, size, self.registrationPort, timeout, 0x0);
  if (result != KERN_SUCCESS) {
    free(handshakeHeader);
    return [[FBSimulatorError
      describeFormat:@"Failed to get the Indigo Reply Port %d", result]
      failBool:error];
  }
  // We have the registration port, so we can now set it.
  self.replyPort = handshakeHeader->msgh_remote_port;
  free(handshakeHeader);
  return YES;
}

- (void)disconnect
{
  if (self.registrationPort == 0) {
    return;
  }
  mach_port_destroy(mach_task_self(), self.registrationPort);
  self.registrationPort = 0;
  self.replyPort = 0;
}

- (void)dealloc
{
  [self disconnect];
}

#pragma mark HID Manipulation

- (BOOL)sendHomeButtonWithError:(NSError **)error
{
  IndigoButtonPayload payload;
  payload.eventSource = ButtonEventSourceHomeButton;
  payload.eventType = ButtonEventTypeDown;
  payload.eventClass = ButtonEventClassHardware;

  // Send the button down
  if (![self sendButtonEventWithPayload:&payload error:error]) {
    return NO;
  }
  // Send the button up
  payload.eventType = ButtonEventTypeUp;
  if (![self sendButtonEventWithPayload:&payload error:error]) {
    return NO;
  }
  return YES;
}

#pragma mark Private

- (BOOL)sendButtonEventWithPayload:(IndigoButtonPayload *)payload error:(NSError **)error
{
  // The home button should have a size of 0x140/320
  mach_msg_size_t messageSize = sizeof(IndigoMessage) + sizeof(IndigoInner);
  IndigoMessage *message = calloc(0x1, messageSize);

  // Set the down payload of the message.
  message->innerSize = sizeof(IndigoInner);
  message->eventType = IndigoEventTypeButton;
  message->inner.field1 = 0x2;
  message->inner.timestamp = mach_absolute_time();

  // Copy the contents of the payload.
  void *destination = &message->inner.unionPayload.buttonPayload;
  void *source = (void *) payload;
  memcpy(destination, source, sizeof(IndigoButtonPayload));

  BOOL result = [self sendIndigoMessage:message size:messageSize error:error];
  free(message);
  return result;
}

- (BOOL)sendIndigoMessage:(IndigoMessage *)message size:(mach_msg_size_t)size error:(NSError **)error
{
  if (self.replyPort == 0) {
    return [[FBSimulatorError
      describe:@"The Reply Port has not been obtained yet. Call -connect: first"]
      failBool:error];
  }

  // Set the header of the message
  message->header.msgh_bits = 0x13;
  message->header.msgh_size = size;
  message->header.msgh_remote_port = self.replyPort;
  message->header.msgh_local_port = 0;
  message->header.msgh_voucher_port = 0;
  message->header.msgh_id = 0;

  mach_msg_return_t result = mach_msg_send((mach_msg_header_t *) message);
  if (result != ERR_SUCCESS) {
    return [[FBSimulatorError
      describeFormat:@"The mach_msg_send failed with error %d", result]
      failBool:error];
  }
  return YES;
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  if (self.registrationPort == 0) {
    return @"Indigo HID Port: Unregistered";
  }
  if (self.replyPort == 0) {
    return [NSString stringWithFormat:@"Indigo HID Port: Registered %d but no reply port", self.registrationPort];
  }
  return [NSString stringWithFormat:@"Indigo HID Port: Registration Port %u, reply port %d", self.registrationPort, self.replyPort];
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
    @"registration_port" : (self.registrationPort == 0 ? NSNull.null : @(self.registrationPort)),
    @"reply_port" : (self.replyPort == 0 ? NSNull.null : @(self.replyPort)),
  };
}

@end
