/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulator.h"
#import "FBSimulator+Private.h"

#import <Cocoa/Cocoa.h>

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>
#import <CoreSimulator/SimDeviceType.h>

#import <FBControlCore/FBControlCore.h>

#import "FBCompositeSimulatorEventSink.h"
#import "FBMutableSimulatorEventSink.h"
#import "FBSimulatorApplicationCommands.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorDiagnostics.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventRelay.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorHistoryGenerator.h"
#import "FBSimulatorLoggingEventSink.h"
#import "FBSimulatorNotificationEventSink.h"
#import "FBSimulatorPool.h"
#import "FBSimulatorResourceManager.h"
#import "FBSimulatorSet.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@implementation FBSimulator

#pragma mark Lifecycle

+ (instancetype)fromSimDevice:(SimDevice *)device configuration:(FBSimulatorConfiguration *)configuration set:(FBSimulatorSet *)set
{
  return [[[FBSimulator alloc]
    initWithDevice:device
    configuration:configuration ?: [FBSimulatorConfiguration inferSimulatorConfigurationFromDevice:device error:nil]
    set:set
    processFetcher:set.processFetcher
    auxillaryDirectory:[FBSimulator auxillaryDirectoryFromSimDevice:device configuration:configuration]
    logger:set.logger]
    attachEventSinkComposition];
}

- (instancetype)initWithDevice:(SimDevice *)device configuration:(FBSimulatorConfiguration *)configuration set:(FBSimulatorSet *)set processFetcher:(FBProcessFetcher *)processFetcher auxillaryDirectory:(NSString *)auxillaryDirectory logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  _configuration = configuration;
  _set = set;
  _processFetcher = processFetcher;
  _auxillaryDirectory = auxillaryDirectory;
  _logger = logger;
  _commandResponders = [FBSimulator commandRespondersForSimulator:self];

  return self;
}

- (instancetype)attachEventSinkComposition
{
  FBSimulatorHistoryGenerator *historyGenerator = [FBSimulatorHistoryGenerator forSimulator:self];
  FBSimulatorNotificationEventSink *notificationSink = [FBSimulatorNotificationEventSink withSimulator:self];
  FBSimulatorLoggingEventSink *loggingSink = [FBSimulatorLoggingEventSink withSimulator:self logger:self.logger];
  FBMutableSimulatorEventSink *mutableSink = [FBMutableSimulatorEventSink new];
  FBSimulatorDiagnostics *diagnosticsSink = [FBSimulatorDiagnostics withSimulator:self];
  FBSimulatorResourceManager *resourceSink = [FBSimulatorResourceManager new];

  FBCompositeSimulatorEventSink *compositeSink = [FBCompositeSimulatorEventSink withSinks:@[historyGenerator, notificationSink, loggingSink, diagnosticsSink, mutableSink, resourceSink]];
  FBSimulatorEventRelay *relay = [[FBSimulatorEventRelay alloc] initWithSimDevice:self.device processFetcher:self.processFetcher sink:compositeSink];

  _historyGenerator = historyGenerator;
  _eventRelay = relay;
  _mutableSink = mutableSink;
  _diagnostics = diagnosticsSink;
  _resourceSink = resourceSink;

  return self;
}

#pragma mark FBiOSTarget

- (NSString *)udid
{
  return self.device.UDID.UUIDString;
}

- (NSString *)name
{
  return self.device.name;
}

- (id<FBControlCoreConfiguration_Device>)deviceConfiguration
{
  return self.configuration.device;
}

- (id<FBControlCoreConfiguration_OS>)osConfiguration
{
  return self.configuration.os;
}

#pragma mark Properties

- (FBSimulatorState)state
{
  return self.device.state;
}

- (FBControlCoreProductFamily)productFamily
{
  int familyID = self.device.deviceType.productFamilyID;
  switch (familyID) {
    case 1:
      return FBControlCoreProductFamilyiPhone;
    case 2:
      return FBControlCoreProductFamilyiPad;
    case 3:
      return FBControlCoreProductFamilyAppleTV;
    case 4:
      return FBControlCoreProductFamilyAppleWatch;
    default:
      return FBControlCoreProductFamilyUnknown;
  }
}

- (NSString *)stateString
{
  return [FBSimulator stateStringFromSimulatorState:self.state];
}

- (NSString *)dataDirectory
{
  return self.device.dataPath;
}

- (BOOL)isAllocated
{
  if (!self.pool) {
    return NO;
  }
  return [self.pool.allocatedSimulators containsObject:self];
}

- (FBProcessInfo *)launchdSimProcess
{
  return self.eventRelay.launchdSimProcess;
}

- (FBSimulatorBridge *)bridge
{
  return self.eventRelay.bridge;
}

- (FBProcessInfo *)containerApplication
{
  return self.eventRelay.containerApplication;
}

- (FBSimulatorHistory *)history
{
  return self.historyGenerator.history;
}

- (id<FBSimulatorEventSink>)eventSink
{
  return self.eventRelay;
}

- (id<FBSimulatorEventSink>)userEventSink
{
  return self.mutableSink.eventSink;
}

- (void)setUserEventSink:(id<FBSimulatorEventSink>)userEventSink
{
  self.mutableSink.eventSink = userEventSink;
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return self.device.hash;
}

- (BOOL)isEqual:(FBSimulator *)simulator
{
  if (![simulator isKindOfClass:self.class]) {
    return NO;
  }
  return [self.device isEqual:simulator.device];
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return [self debugDescription];
}

- (NSString *)debugDescription
{
  return [NSString stringWithFormat:
    @"Name %@ | UUID %@ | State %@ | %@ | %@",
    self.name,
    self.udid,
    self.device.stateString,
    self.launchdSimProcess,
    self.containerApplication
  ];
}

- (NSString *)shortDescription
{
  return [NSString stringWithFormat:@"Simulator %@", self.udid];
}

#pragma mark FBJSONSerializable

- (NSDictionary *)jsonSerializableRepresentation
{
  return @{
    @"name" : self.device.name,
    @"state" : self.device.stateString,
    @"udid" : self.udid
  };
}

#pragma mark Forwarding

- (id)forwardingTargetForSelector:(SEL)selector
{
  for (id target in self.commandResponders) {
    if ([target respondsToSelector:selector]) {
      return target;
    }
  }
  return nil;
}

+ (NSArray *)commandRespondersForSimulator:(FBSimulator *)simulator
{
  return @[
    [FBSimulatorApplicationCommands withSimulator:simulator],
  ];
}

+ (NSString *)auxillaryDirectoryFromSimDevice:(SimDevice *)device configuration:(FBSimulatorConfiguration *)configuration
{
  if (!configuration.auxillaryDirectory) {
    return [device.dataPath stringByAppendingPathComponent:@"fbsimulatorcontrol"];
  }
  return [configuration.auxillaryDirectory stringByAppendingPathComponent:device.UDID.UUIDString];
}

@end

#pragma clang diagnostic pop
