/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorHID.h"

#import <objc/runtime.h>

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceType.h>

#import <CoreGraphics/CoreGraphics.h>

#import <SimulatorApp/Indigo.h>

#import <SimulatorKit/SimDeviceLegacyClient.h>

#import <mach/mach.h>
#import <mach/mach_time.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"

@interface FBSimulatorHID ()

@property (nonatomic, strong, readonly) FBSimulatorIndigoHID *indigo;
@property (nonatomic, assign, readonly) CGSize mainScreenSize;

@end

@interface FBSimulatorHID_Reimplemented : FBSimulatorHID

@property (nonatomic, assign, readwrite) mach_port_t registrationPort;
@property (nonatomic, assign, readwrite) mach_port_t replyPort;

- (instancetype)initWithIndigo:(FBSimulatorIndigoHID *)indigo mainScreenSize:(CGSize)mainScreenSize registrationPort:(mach_port_t)registrationPort;

@end

@interface FBSimulatorHID_SimulatorKit : FBSimulatorHID

@property (nonatomic, strong, nullable, readonly) SimDeviceLegacyClient *client;

- (instancetype)initWithIndigo:(FBSimulatorIndigoHID *)indigo mainScreenSize:(CGSize)mainScreenSize client:(SimDeviceLegacyClient *)client;

@end

@implementation FBSimulatorHID

#pragma mark Initializers

static const char*SimulatorHIDClientClassName = "SimulatorKit.SimDeviceLegacyHIDClient";

+ (instancetype)hidPortForSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  Class clientClass = objc_lookUpClass(SimulatorHIDClientClassName);
  if (clientClass) {
    return [self simulatorKitHidPortForSimulator:simulator clientClass:clientClass error:error];
  }
  return [self reimplementedHidPortForSimulator:simulator error:error];
}

+ (instancetype)simulatorKitHidPortForSimulator:(FBSimulator *)simulator clientClass:(Class)clientClass error:(NSError **)error
{
  NSError *innerError = nil;
  SimDeviceLegacyClient *client = [[clientClass alloc] initWithDevice:simulator.device error:&innerError];
  if (!client) {
    return [[[FBSimulatorError
      describeFormat:@"Could not create instance of %@", NSStringFromClass(clientClass)]
      causedBy:innerError]
      fail:error];
  }
  CGSize mainScreenSize = simulator.device.deviceType.mainScreenSize;
  return [[FBSimulatorHID_SimulatorKit alloc] initWithIndigo:FBSimulatorIndigoHID.defaultHID mainScreenSize:mainScreenSize client:client];
}

+ (instancetype)reimplementedHidPortForSimulator:(FBSimulator *)simulator error:(NSError **)error
{
  // We have to create this before boot, return early if this isn't true.
  if (simulator.state != FBSimulatorStateShutdown) {
    return [[FBSimulatorError
     describeFormat:@"Simulator must be shut down to create a HID port is %@", simulator.stateString]
     fail:error];
  }

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

  CGSize mainScreenSize = simulator.device.deviceType.mainScreenSize;
  return [[FBSimulatorHID_Reimplemented alloc] initWithIndigo:FBSimulatorIndigoHID.reimplemented mainScreenSize:mainScreenSize registrationPort:registrationPort];
}

- (instancetype)initWithIndigo:(FBSimulatorIndigoHID *)indigo mainScreenSize:(CGSize)mainScreenSize
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _indigo = indigo;
  _mainScreenSize = mainScreenSize;

  return self;
}

#pragma mark Lifecycle

- (BOOL)connect:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return NO;
}

- (void)disconnect
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

- (void)dealloc
{
  [self disconnect];
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark FBJSONSerializable

- (id)jsonSerializableRepresentation
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark HID Manipulation

- (BOOL)sendKeyboardEventWithDirection:(FBSimulatorHIDDirection)direction keyCode:(unsigned int)keycode error:(NSError **)error
{
  return [self sendIndigoMessageData:[self.indigo keyboardWithDirection:direction keyCode:keycode] error:error];
}

- (BOOL)sendButtonEventWithDirection:(FBSimulatorHIDDirection)direction button:(FBSimulatorHIDButton)button error:(NSError **)error
{
  return [self sendIndigoMessageData:[self.indigo buttonWithDirection:direction button:button] error:error];
}

- (BOOL)sendTouchWithType:(FBSimulatorHIDDirection)type x:(double)x y:(double)y error:(NSError **)error
{
  return [self sendIndigoMessageData:[self.indigo touchScreenSize:self.mainScreenSize direction:type x:x y:y] error:error];
}

#pragma mark Private

- (BOOL)sendIndigoMessageData:(NSData *)data error:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return NO;
}

@end

@implementation FBSimulatorHID_Reimplemented

#pragma mark Initializers

- (instancetype)initWithIndigo:(FBSimulatorIndigoHID *)indigo mainScreenSize:(CGSize)mainScreenSize registrationPort:(mach_port_t)registrationPort
{
  self = [super initWithIndigo:indigo mainScreenSize:mainScreenSize];
  if (!self) {
    return nil;
  }

  _registrationPort = registrationPort;
  _replyPort = 0;

  return self;
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

#pragma mark FBJSONSerializable

- (id)jsonSerializableRepresentation
{
  return @{
    @"registration_port" : (self.registrationPort == 0 ? NSNull.null : @(self.registrationPort)),
    @"reply_port" : (self.replyPort == 0 ? NSNull.null : @(self.replyPort)),
  };
}

#pragma mark Lifecycle

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

#pragma mark Private

- (BOOL)sendIndigoMessageData:(NSData *)data error:(NSError **)error
{
  if (self.replyPort == 0) {
    return [[FBSimulatorError
      describe:@"The Reply Port has not been obtained yet. Call -connect: first"]
      failBool:error];
  }

  // Extract the message
  IndigoMessage *message = (IndigoMessage *) data.bytes;
  mach_msg_size_t size = (mach_msg_size_t) data.length;

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

@end

@implementation FBSimulatorHID_SimulatorKit

- (instancetype)initWithIndigo:(FBSimulatorIndigoHID *)indigo mainScreenSize:(CGSize)mainScreenSize client:(SimDeviceLegacyClient *)client
{
  self = [super initWithIndigo:indigo mainScreenSize:mainScreenSize];
  if (!self) {
    return nil;
  }

  _client = client;

  return self;
}

#pragma mark Lifecycle

- (BOOL)connect:(NSError **)error
{
  return YES;
}

- (void)disconnect
{
  _client = nil;
}

#pragma mark Private

- (BOOL)sendIndigoMessageData:(NSData *)data error:(NSError **)error
{
  // The event is delivered asynchronously.
  // Therefore copy the message and let the client manage the lifecycle of it.
  size_t size = (mach_msg_size_t) data.length;
  IndigoMessage *message = malloc(size);
  memcpy(message, data.bytes, size);

  [self.client sendWithMessage:message freeWhenDone:YES completionQueue:dispatch_get_main_queue() completion:^(id _){}];
  return YES;
}

@end
