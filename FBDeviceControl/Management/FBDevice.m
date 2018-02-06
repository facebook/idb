/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDevice.h"
#import "FBDevice+Private.h"

#import <IDEiOSSupportCore/DVTiOSDevice.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

#import <FBControlCore/FBControlCore.h>

#import "FBAMDevice.h"
#import "FBDeviceApplicationCommands.h"
#import "FBDeviceControlError.h"
#import "FBDeviceLogCommands.h"
#import "FBDeviceScreenshotCommands.h"
#import "FBDeviceSet+Private.h"
#import "FBDeviceVideoRecordingCommands.h"
#import "FBDeviceXCTestCommands.h"
#import "FBiOSDeviceOperator.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@implementation FBDevice

@synthesize deviceOperator = _deviceOperator;
@synthesize logger = _logger;

#pragma mark Initializers

- (instancetype)initWithSet:(FBDeviceSet *)set amDevice:(FBAMDevice *)amDevice logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _set = set;
  _amDevice = amDevice;
  _logger = [logger withPrefix:[NSString stringWithFormat:@"%@: ", amDevice.udid]];
  _forwarder = [FBiOSTargetCommandForwarder forwarderWithTarget:self commandClasses:FBDevice.commandResponders memoize:YES];

  return self;
}

#pragma mark FBiOSTarget

- (NSArray<Class> *)actionClasses
{
  return @[
    FBTestLaunchConfiguration.class,
  ];
}

- (NSString *)udid
{
  return self.amDevice.udid;
}

- (NSString *)name
{
  return self.amDevice.deviceName;
}

- (FBArchitecture)architecture
{
  return self.amDevice.architecture;
}

- (NSString *)auxillaryDirectory
{
  return [[[NSHomeDirectory()
    stringByAppendingPathComponent:@"Library"]
    stringByAppendingPathComponent:@"FBDeviceControl"]
    stringByAppendingPathComponent:self.udid];
}

- (FBSimulatorState)state
{
  return FBSimulatorStateBooted;
}

- (FBiOSTargetType)targetType
{
  return FBiOSTargetTypeDevice;
}

- (FBProcessInfo *)containerApplication
{
  return nil;
}

- (FBProcessInfo *)launchdProcess
{
  return nil;
}

- (FBDeviceType *)deviceType
{
  return self.amDevice.deviceConfiguration;
}

- (FBOSVersion *)osVersion
{
  return self.amDevice.osConfiguration;
}

- (FBiOSTargetDiagnostics *)diagnostics
{
  return [[FBiOSTargetDiagnostics alloc] initWithStorageDirectory:self.auxillaryDirectory];
}

- (dispatch_queue_t)workQueue
{
  return dispatch_get_main_queue();
}

- (dispatch_queue_t)asyncQueue
{
  return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
}

- (NSComparisonResult)compare:(id<FBiOSTarget>)target
{
  return FBiOSTargetComparison(self, target);
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return [self debugDescription];
}

- (NSString *)debugDescription
{
  return [FBiOSTargetFormat.fullFormat format:self];
}

- (NSString *)shortDescription
{
  return [FBiOSTargetFormat.defaultFormat format:self];
}

#pragma mark FBJSONSerializable

- (NSDictionary *)jsonSerializableRepresentation
{
  return [FBiOSTargetFormat.fullFormat extractFrom:self];
}

#pragma mark Properties

- (id<FBDeviceOperator>)deviceOperator
{
  if (_deviceOperator == nil) {
    _deviceOperator = [FBiOSDeviceOperator forDevice:self];
  }
  return _deviceOperator;
}

- (NSString *)modelName
{
  return self.amDevice.modelName;
}

- (NSString *)systemVersion
{
  return self.amDevice.systemVersion;
}

- (FBiOSTargetScreenInfo *)screenInfo
{
  return nil;
}

#pragma mark Forwarding

+ (NSMutableArray<Class> *)commandResponders
{
  static dispatch_once_t onceToken;
  static NSMutableArray<Class> *commandClasses;
  dispatch_once(&onceToken, ^{
    commandClasses = [[NSMutableArray alloc] init];
    [commandClasses addObjectsFromArray:@[
      FBDeviceApplicationCommands.class,
      FBDeviceLogCommands.class,
      FBDeviceScreenshotCommands.class,
      FBDeviceVideoRecordingCommands.class,
      FBDeviceXCTestCommands.class,
    ]];
  });
  return commandClasses;
}

+ (BOOL)addForwardingCommandClass:(Class)class error:(NSError **)error
{
  if (![class conformsToProtocol:@protocol(FBiOSTargetCommand)]){
    return [[FBDeviceControlError
      describe:@"Failed to add forwarding class. Class does not conform to FBiOSTargetCommand protocol."]
      failBool:error];
  }
  [[self commandResponders] addObject:class];
  return YES;
}

- (id)forwardingTargetForSelector:(SEL)selector
{
  // Try the forwarder.
  id command = [self.forwarder forwardingTargetForSelector:selector];
  if (command) {
    return command;
  }
  // Otherwise try the operator
  if ([FBiOSDeviceOperator instancesRespondToSelector:selector]) {
    return self.deviceOperator;
  }
  // Nothing left.
  return [super forwardingTargetForSelector:selector];
}

- (BOOL)conformsToProtocol:(Protocol *)protocol
{
  if ([super conformsToProtocol:protocol]) {
    return YES;
  }
  if ([self.forwarder conformsToProtocol:protocol]) {
    return  YES;
  }

  return NO;
}

@end

#pragma clang diagnostic pop
