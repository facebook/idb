/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDeviceSet.h"
#import "FBDeviceSet+Private.h"

#import <DTDeviceKitBase/DTDKRemoteDeviceConsoleController.h>
#import <DTDeviceKitBase/DTDKRemoteDeviceToken.h>

#import <DTXConnectionServices/DTXChannel.h>
#import <DTXConnectionServices/DTXMessage.h>

#import <DVTFoundation/DVTDeviceManager.h>
#import <DVTFoundation/DVTFuture.h>

#import <IDEiOSSupportCore/DVTiOSDevice.h>

#import <FBControlCore/FBControlCore.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

#import <objc/runtime.h>

#import "FBDeviceControlFrameworkLoader.h"
#import "FBDevice+Private.h"
#import "FBAMDevice.h"
#import "FBDeviceInflationStrategy.h"

static const NSTimeInterval FBDeviceSetDeviceManagerTickleTime = 2;

@implementation FBDeviceSet

@synthesize allDevices = _allDevices;

#pragma mark Initializers

+ (void)initialize
{
  [FBDeviceControlFrameworkLoader initializeEssentialFrameworks];
}

- (void)primeDeviceManager
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    // It seems that searching for a device that does not exist will cause all available devices/simulators etc. to be cached.
    // There's probably a better way of fetching all the available devices, but this appears to work well enough.
    // This means that all the cached available devices can then be found.
    [FBDeviceControlFrameworkLoader initializeXCodeFrameworks];

    DVTDeviceManager *deviceManager = [objc_lookUpClass("DVTDeviceManager") defaultDeviceManager];
    [self.logger.debug logFormat:@"Quering device manager for %f seconds to cache devices", FBDeviceSetDeviceManagerTickleTime];
    [deviceManager searchForDevicesWithType:nil options:@{@"id" : @"I_DONT_EXIST_AT_ALL"} timeout:FBDeviceSetDeviceManagerTickleTime error:nil];
    [self.logger.debug log:@"Finished querying devices to cache them"];
  });
}

+ (nullable instancetype)defaultSetWithLogger:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error
{
  static dispatch_once_t onceToken;
  static FBDeviceSet *deviceSet = nil;
  dispatch_once(&onceToken, ^{
    deviceSet = [[FBDeviceSet alloc] initWithLogger:logger];
  });
  return deviceSet;
}

- (instancetype)initWithLogger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _logger = logger;
  _allDevices = @[];

  return self;
}

#pragma mark Querying

- (NSArray<FBDevice *> *)query:(FBiOSTargetQuery *)query
{
  if ([query excludesAll:FBiOSTargetTypeDevice]) {
    return @[];
  }
  return (NSArray<FBDevice *> *)[query filter:self.allDevices];
}

- (nullable FBDevice *)deviceWithUDID:(NSString *)udid
{
  FBiOSTargetQuery *query = [FBiOSTargetQuery udids:@[udid]];
  return [[self query:query] firstObject];
}

#pragma mark Properties

- (NSArray<FBDevice *> *)allDevices
{
  _allDevices = [[self.inflationStrategy
    inflateFromDevices:FBAMDevice.allDevices existingDevices:_allDevices]
    sortedArrayUsingSelector:@selector(compare:)];
  return _allDevices;
}

#pragma mark Predicates

+ (NSPredicate *)predicateDeviceWithUDID:(NSString *)udid
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBDevice *device, id _) {
    return [device.udid isEqualToString:udid];
  }];
}

#pragma mark Private

- (FBDeviceInflationStrategy *)inflationStrategy
{
  return [FBDeviceInflationStrategy forSet:self];
}

- (nullable DVTiOSDevice *)dvtDeviceWithUDID:(NSString *)udid
{
  [self primeDeviceManager];
  NSDictionary<NSString *, DVTiOSDevice *> *dvtDevices = [FBDeviceSet keyDVTDevicesByUDID:[objc_lookUpClass("DVTiOSDevice") alliOSDevices]];
  return dvtDevices[udid];
}

+ (NSDictionary<NSString *, DVTiOSDevice *> *)keyDVTDevicesByUDID:(NSArray<DVTiOSDevice *> *)devices
{
  NSMutableDictionary<NSString *, DVTiOSDevice *> *dictionary = [NSMutableDictionary dictionary];
  for (DVTiOSDevice *device in devices) {
    dictionary[device.identifier] = device;
  }
  return [dictionary copy];
}

+ (NSDictionary<NSString *, FBAMDevice *> *)keyAMDevicesByUDID:(NSArray<FBAMDevice *> *)devices
{
  NSMutableDictionary<NSString *, FBAMDevice *> *dictionary = [NSMutableDictionary dictionary];
  for (FBAMDevice *device in devices) {
    dictionary[device.udid] = device;
  }
  return [dictionary copy];
}

@end
