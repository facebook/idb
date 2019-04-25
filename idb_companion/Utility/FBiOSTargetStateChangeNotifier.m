/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSTargetStateChangeNotifier.h"

#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBDeviceControl/FBDeviceControl.h>

@interface FBiOSTargetStateChangeNotifier () <FBiOSTargetSetDelegate>

@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readwrite) FBDeviceSet *deviceSet;
@property (nonatomic, strong, readwrite) FBSimulatorSet *simulatorSet;
@property (nonatomic, strong, readwrite) id<FBDataConsumer> consumer;

@end

@implementation FBiOSTargetStateChangeNotifier

#pragma mark Initializers

+ (instancetype)notifierWithConsumer:(id<FBDataConsumer>)consumer notifierForLogger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithConsumer:consumer logger:logger];
}

+ (instancetype)stdoutNotifierWithLogger:(id<FBControlCoreLogger>)logger
{
  id<FBDataConsumer> consumer = [FBFileWriter syncWriterWithFileHandle:NSFileHandle.fileHandleWithStandardOutput];
  return [self notifierWithConsumer:consumer notifierForLogger:logger];
}

- (instancetype)initWithConsumer:(id<FBDataConsumer>)consumer logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumer = consumer;
  _logger = logger;

  return self;
}

#pragma mark Public

- (FBFuture<FBFuture<NSNull *> *> *)startNotifier
{
  NSError *error = nil;
  self.deviceSet = [FBDeviceSet defaultSetWithLogger:_logger error:&error delegate:self];
  if (!self.deviceSet) {
    [FBFuture futureWithError:error];
  }
  FBSimulatorControlConfiguration *configuration = [FBSimulatorControlConfiguration
    configurationWithDeviceSetPath:nil
    options:0
    logger:self.logger
    reporter:nil];
  FBSimulatorServiceContext *serviceContext = [FBSimulatorServiceContext sharedServiceContext];
  SimDeviceSet *simDeviceSet = [serviceContext createDeviceSetWithConfiguration:configuration error:&error];
  if (!simDeviceSet) {
    return [FBFuture futureWithError:error];
  }
  self.simulatorSet = [FBSimulatorSet setWithConfiguration:configuration deviceSet:simDeviceSet delegate:self logger:self.logger reporter:nil error:&error];
  if (!self.simulatorSet) {
    return [FBFuture futureWithError:error];
  }
  [self reportInitialState];

  // The notifier never terminates
  return [FBFuture futureWithResult:FBMutableFuture.future];
}

#pragma mark Private

- (void)reportInitialState
{
  for (FBDevice *device in self.deviceSet.allDevices) {
    [self targetDidUpdate:[[FBiOSTargetStateUpdate alloc] initWithUDID:device.udid state:device.state type:FBiOSTargetTypeDevice name:device.name osVersion:device.osVersion architecture:device.architecture]];
  }
  for (FBSimulator *simulator in self.simulatorSet.allSimulators) {
    [self targetDidUpdate:[[FBiOSTargetStateUpdate alloc] initWithUDID:simulator.udid state:simulator.state type:FBiOSTargetTypeSimulator name:simulator.name osVersion:simulator.osVersion architecture:simulator.architecture]];
  }
  [self endOfInitialState];
}

- (void)writeJSONObject:(NSDictionary<NSString *, id> *)dictionary
{
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:&error];
  if (!data) {
    [self.logger logFormat:@"error writing update to consumer %@",error];
    return;
  }
  [self.consumer consumeData:data];
  [self.consumer consumeData:FBDataBuffer.newlineTerminal];
}

#pragma mark FBiOSTargetSet Delegate Methods

- (void)targetDidUpdate:(FBiOSTargetStateUpdate *)update
{
  [self writeJSONObject:update.jsonSerializableRepresentation];
}

- (void)endOfInitialState
{
  [self writeJSONObject:@{@"initial_state_ended": @YES}];
}

@end
