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
#import "FBSimulatorPool+Private.h"

#import <AppKit/AppKit.h>

#import <CoreSimulator/SimDevice.h>
#import <CoreSimulator/SimDeviceSet.h>
#import <CoreSimulator/SimDeviceType.h>

#import "FBCompositeSimulatorEventSink.h"
#import "FBMutableSimulatorEventSink.h"
#import "FBProcessInfo.h"
#import "FBProcessQuery.h"
#import "FBSimulator+Helpers.h"
#import "FBSimulatorConfiguration+CoreSimulator.h"
#import "FBSimulatorConfiguration.h"
#import "FBSimulatorControlConfiguration.h"
#import "FBSimulatorControlGlobalConfiguration.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventRelay.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorHistoryGenerator.h"
#import "FBSimulatorLoggingEventSink.h"
#import "FBSimulatorDiagnostics.h"
#import "FBSimulatorNotificationEventSink.h"
#import "FBSimulatorPool.h"
#import "FBTaskExecutor.h"

@implementation FBSimulator

#pragma mark Lifecycle

+ (instancetype)fromSimDevice:(SimDevice *)device configuration:(FBSimulatorConfiguration *)configuration pool:(FBSimulatorPool *)pool
{
  return [[[FBSimulator alloc]
    initWithDevice:device
    configuration:configuration ?: [FBSimulatorConfiguration inferSimulatorConfigurationFromDevice:device error:nil]
    pool:pool
    query:pool.processQuery
    auxillaryDirectory:[FBSimulator auxillaryDirectoryFromSimDevice:device configuration:configuration]
    logger:pool.logger]
    attachEventSinkComposition];
}

- (instancetype)initWithDevice:(SimDevice *)device configuration:(FBSimulatorConfiguration *)configuration pool:(FBSimulatorPool *)pool query:(FBProcessQuery *)query auxillaryDirectory:(NSString *)auxillaryDirectory logger:(id<FBSimulatorLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;
  _configuration = configuration;
  _pool = pool;
  _processQuery = query;
  _auxillaryDirectory = auxillaryDirectory;
  _logger = logger;

  return self;
}

- (instancetype)attachEventSinkComposition
{
  FBSimulatorHistoryGenerator *historyGenerator = [FBSimulatorHistoryGenerator forSimulator:self];
  FBSimulatorNotificationEventSink *notificationSink = [FBSimulatorNotificationEventSink withSimulator:self];
  FBSimulatorLoggingEventSink *loggingSink = [FBSimulatorLoggingEventSink withSimulator:self logger:self.logger];
  FBMutableSimulatorEventSink *mutableSink = [FBMutableSimulatorEventSink new];
  FBSimulatorDiagnostics *diagnosticsSink = [FBSimulatorDiagnostics withSimulator:self];

  FBCompositeSimulatorEventSink *compositeSink = [FBCompositeSimulatorEventSink withSinks:@[historyGenerator, notificationSink, loggingSink, diagnosticsSink, mutableSink]];
  FBSimulatorEventRelay *relay = [[FBSimulatorEventRelay alloc] initWithSimDevice:self.device processQuery:self.processQuery sink:compositeSink];

  _historyGenerator = historyGenerator;
  _eventRelay = relay;
  _mutableSink = mutableSink;
  _diagnostics = diagnosticsSink;

  return self;
}

#pragma mark Properties

- (NSString *)name
{
  return self.device.name;
}

- (NSString *)udid
{
  return self.device.UDID.UUIDString;
}

- (FBSimulatorState)state
{
  return (NSInteger) self.device.state;
}

- (FBSimulatorProductFamily)productFamily
{
  int familyID = self.device.deviceType.productFamilyID;
  switch (familyID) {
    case 1:
      return FBSimulatorProductFamilyiPhone;
    case 2:
      return FBSimulatorProductFamilyiPad;
    case 3:
      return FBSimulatorProductFamilyAppleTV;
    case 4:
      return FBSimulatorProductFamilyAppleWatch;
    default:
      return FBSimulatorProductFamilyUnknown;
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

- (FBSimulatorFramebuffer *)framebuffer
{
  return self.eventRelay.framebuffer;
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

#pragma mark FBJSONSerializationDescribeable

- (NSDictionary *)jsonSerializableRepresentation
{
  return @{
    @"name" : self.device.name,
    @"state" : self.device.stateString,
    @"udid" : self.udid
  };
}

#pragma mark Private

+ (NSString *)auxillaryDirectoryFromSimDevice:(SimDevice *)device configuration:(FBSimulatorConfiguration *)configuration
{
  if (!configuration.auxillaryDirectory) {
    return [device.dataPath stringByAppendingPathComponent:@"fbsimulatorcontrol"];
  }
  return [configuration.auxillaryDirectory stringByAppendingPathComponent:device.UDID.UUIDString];
}

@end
