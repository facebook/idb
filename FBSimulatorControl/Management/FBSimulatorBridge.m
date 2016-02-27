/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorBridge.h"

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceType.h>

#import <SimulatorBridge/SimulatorBridge-Protocol.h>

#import <SimulatorKit/SimDeviceFramebufferService.h>

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorFramebuffer.h"
#import "FBSimulatorLaunchConfiguration.h"

@interface FBSimulatorBridge ()

@property (nonatomic, strong, readonly) id<FBSimulatorEventSink> eventSink;
@property (nonatomic, strong, readonly) dispatch_group_t teardownGroup;

@property (nonatomic, strong, readwrite) FBSimulatorFramebuffer *framebuffer;
@property (nonatomic, assign, readwrite) mach_port_t hidPort;
@property (nonatomic, strong, readwrite) id<SimulatorBridge> bridge;

@end

@implementation FBSimulatorBridge

#pragma mark Initializers

+ (instancetype)bootSimulator:(FBSimulator *)simulator withConfiguration:(FBSimulatorLaunchConfiguration *)configuration andAttachBridgeWithError:(NSError **)error
{
  // If you're curious about where the knowledege for these parts of the CoreSimulator.framework comes from, take a look at:
  // $DEVELOPER_DIR/Platforms/iPhoneSimulator.platform/Developer/Library/CoreSimulator/Profiles/Runtimes/iOS [VERSION].simruntime/Contents/Resources/profile.plist
  // as well as the dissasembly for CoreSimulator.framework, SimulatorKit.Framework & the Simulator.app Executable.

  // Creating the Framebuffer with the 'mainScreen' constructor will return a 'PurpleFBServer' and attach it to the '_registeredServices' ivar.
  // This is the Framebuffer for the Simulator's main screen, which is distinct from 'PurpleFBTVOut' and 'Stark' Framebuffers for External Displays and CarPlay.
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
  CGSize scaledSize = [configuration scaleSize:size];

  // Create the service
  SimDeviceFramebufferService *framebufferService = [NSClassFromString(@"SimDeviceFramebufferService") framebufferServiceWithPort:purpleServerPort deviceDimensions:size scaledDimensions:scaledSize error:&innerError];
  if (!framebufferService) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to create the Main Screen Framebuffer for device %@", simulator.device]
      causedBy:innerError]
      fail:error];
  }

  // As above with the 'PurpleFBServer', a 'IndigoHIDRegistrationPort' is needed in order for the synthesis of touch events to work appropriately.
  // If this is not set you will see the following logger message in the System log upon booting the simulator
  // 'backboardd[10667]: BKHID: Unable to open Indigo HID system'
  // The dissasembly for backboardd shows that this will happen when the call to 'IndigoHIDSystemSpawnLoopback' fails.
  // Simulator.app creates a Mach Port for the 'IndigoHIDRegistrationPort' and therefore succeeds in the above call.
  // As with 'PurpleFBServer' this can be registered with 'register-head-services'
  // The first step is to create the mach port
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

  // The 'register-head-services' option will attach the existing 'frameBufferService' when the Simulator is booted.
  // Simulator.app behaves similarly, except we can't peek at the Framebuffer as it is in a protected process since Xcode 7.
  // Prior to Xcode 6 it was possible to shim into the Simulator process but codesigning now prevents this https://gist.github.com/lawrencelomax/27bdc4e8a433a601008f
  NSDictionary *options = @{
    @"register-head-services" : @YES
  };

  // Booting is simpler than the Simulator.app launch process since the caller calls CoreSimulator Framework directly.
  // Just pass in the options to ensure that the framebuffer service is registered when the Simulator is booted.
  BOOL success = [simulator.device bootWithOptions:options error:&innerError];
  if (!success) {
    return [[[FBSimulatorError
      describeFormat:@"Failed to boot Simulator with options %@", options]
      causedBy:innerError]
      fail:error];
  }

  // Connect to the expected-to-be-running CoreSimulatorBridge running inside the Simulator.
  // This mimics the behaviour of Simulator.app, which just looks up the service then connects to the distant object over xpc.
  mach_port_t port = [simulator.device lookup:@"com.apple.iphonesimulator.bridge" error:&innerError];
  if (port == 0) {
    return [[[FBSimulatorError
      describe:@"Could not lookup mach port for 'com.apple.iphonesimulator.bridge'"]
      inSimulator:simulator]
      fail:error];
  }
  NSPort *machPort = [NSMachPort portWithMachPort:port];
  NSConnection *connection = [NSConnection connectionWithReceivePort:nil sendPort:machPort];
  NSDistantObject *distantObject = [connection rootProxy];
  if (![distantObject respondsToSelector:@selector(setLocationScenarioWithPath:)]) {
    return [[[FBSimulatorError
      describeFormat:@"Distant Object '%@' for 'com.apple.iphonesimulator.bridge' at port %d isn't a SimulatorBridge", distantObject, port]
      inSimulator:simulator]
      fail:error];
  }

  // Create and start the consumer of the Framebuffer Service.
  // The launch configuration will define the way that the Framebuffer is consumed.
  // Then the simulator's event sink should be notified with the created framebuffer object.
  FBSimulatorFramebuffer *framebuffer = [FBSimulatorFramebuffer withFramebufferService:framebufferService configuration:configuration simulator:simulator];
  [framebuffer startListeningInBackground];

  // Create the bridge and broadcast the availability
  FBSimulatorBridge *bridge = [[self alloc] initWithFramebuffer:framebuffer hidPort:hidPort bridge:(id<SimulatorBridge>)distantObject eventSink:simulator.eventSink];
  [simulator.eventSink bridgeDidConnect:bridge];

  return bridge;
}

- (instancetype)initWithFramebuffer:(FBSimulatorFramebuffer *)framebuffer hidPort:(mach_port_t)hidPort bridge:(id<SimulatorBridge>)bridge eventSink:(id<FBSimulatorEventSink>)eventSink
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
    @"Bridge: Framebuffer (%@) | hid_port %d | Remote Bridge (%@)",
    self.framebuffer.description,
    self.hidPort,
    self.bridge
  ];
}

#pragma mark FBJSONSerializationDescribeable Implementation

- (id)jsonSerializableRepresentation
{
  return @{
    @"framebuffer" : self.framebuffer.jsonSerializableRepresentation,
    @"hid_port" : @(self.hidPort)
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

@end
