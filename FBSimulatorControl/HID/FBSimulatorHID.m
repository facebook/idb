/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

@property (nonatomic, strong, readonly) SimDeviceLegacyClient *client;

- (instancetype)initWithIndigo:(FBSimulatorIndigoHID *)indigo client:(SimDeviceLegacyClient *)client mainScreenSize:(CGSize)mainScreenSize mainScreenScale:(float)mainScreenScale queue:(dispatch_queue_t)queue;

@end

@implementation FBSimulatorHID

#pragma mark Initializers

static const char *SimulatorHIDClientClassName = "SimulatorKit.SimDeviceLegacyHIDClient";

+ (dispatch_queue_t)workQueue
{
  return dispatch_queue_create("com.facebook.fbsimulatorcontrol.hid", DISPATCH_QUEUE_SERIAL);
}

+ (FBFuture<FBSimulatorHID *> *)hidForSimulator:(FBSimulator *)simulator
{
  Class clientClass = objc_lookUpClass(SimulatorHIDClientClassName);
  NSParameterAssert(clientClass);
  NSError *error = nil;
  SimDeviceLegacyClient *client = [[clientClass alloc] initWithDevice:simulator.device error:&error];
  if (!client) {
    return [[[FBSimulatorError
      describeFormat:@"Could not create instance of %@", NSStringFromClass(clientClass)]
      causedBy:error]
      failFuture];
  }
  FBSimulatorIndigoHID *indigo = [FBSimulatorIndigoHID simulatorKitHIDWithError:&error];
  if (!indigo) {
    return nil;
  }
  CGSize mainScreenSize = simulator.device.deviceType.mainScreenSize;
  float scale = simulator.device.deviceType.mainScreenScale;
  FBSimulatorHID *hid = [[self alloc] initWithIndigo:indigo client:client mainScreenSize:mainScreenSize mainScreenScale:scale queue:self.workQueue];
  return [FBFuture futureWithResult:hid];
}

- (instancetype)initWithIndigo:(FBSimulatorIndigoHID *)indigo client:(SimDeviceLegacyClient *)client mainScreenSize:(CGSize)mainScreenSize mainScreenScale:(float)mainScreenScale queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _indigo = indigo;
  _client = client;
  _mainScreenSize = mainScreenSize;
  _queue = queue;
  _mainScreenScale = mainScreenScale;

  return self;
}

#pragma mark HID Manipulation

- (FBFuture<NSNull *> *)sendEvent:(NSData *)data
{
  return [FBFuture onQueue:self.queue resolve:^{
    FBMutableFuture<NSNull *> *future = FBMutableFuture.future;
    [self sendIndigoMessageData:data completionQueue:self.queue completion:^(NSError *error) {
      if (error) {
        [future resolveWithError:error];
      } else {
        [future resolveWithResult:NSNull.null];
      }
    }];
    return future;
  }];
}

- (void)sendIndigoMessageData:(NSData *)data completionQueue:(dispatch_queue_t)completionQueue completion:(void (^)(NSError *))completion
{
  // The event is delivered asynchronously.
  // Therefore copy the message and let the client manage the lifecycle of it.
  // The free of the buffer is performed by the client and the NSData will free when it falls out of scope.
  size_t size = (mach_msg_size_t) data.length;
  IndigoMessage *message = malloc(size);
  memcpy(message, data.bytes, size);
  [self.client sendWithMessage:message freeWhenDone:YES completionQueue:completionQueue completion:completion];
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"SimulatorKit HID %@", self.client];
}

#pragma mark Lifecycle

- (FBFuture<NSNull *> *)connect
{
  if (!self.client) {
    return [[FBSimulatorError
      describe:@"Cannot Connect, HID client has already been disposed of"]
      failFuture];
  }
  return FBFuture.empty;
}

- (FBFuture<NSNull *> *)disconnect
{
  _client = nil;
  return FBFuture.empty;
}


@end
