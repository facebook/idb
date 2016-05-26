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

#import "FBDeviceControlFrameworkLoader.h"
#import "FBiOSDeviceOperator+Private.h"
#import "FBDevice+Private.h"
#import "FBAMDevice.h"

static const NSTimeInterval FBDeviceSetDeviceManagerTickleTime = 1;

@implementation FBDeviceSet

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

    DVTDeviceManager *deviceManager = [NSClassFromString(@"DVTDeviceManager") defaultDeviceManager];
    [self.logger.debug logFormat:@"Quering device manager for %f seconds to cache devices", FBDeviceSetDeviceManagerTickleTime];
    [deviceManager searchForDevicesWithType:nil options:@{@"id" : @"I_DONT_EXIST_AT_ALL"} timeout:FBDeviceSetDeviceManagerTickleTime error:nil];
    [self.logger.debug log:@"Finished querying devices to cache them"];
  });
}

+ (instancetype)defaultSetWithLogger:(id<FBControlCoreLogger>)logger error:(NSError **)error
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

  return self;
}

#pragma mark Public

- (nullable FBDevice *)deviceWithUDID:(NSString *)udid
{
  return [[self.allDevices
    filteredArrayUsingPredicate:[FBDeviceSet predicateDeviceWithUDID:udid]]
    firstObject];
}

#pragma mark Private

- (nullable DVTiOSDevice *)dvtDeviceWithUDID:(NSString *)udid
{
  [self primeDeviceManager];
  NSDictionary<NSString *, DVTiOSDevice *> *dvtDevices = [FBDeviceSet keyDVTDevicesByUDID:[NSClassFromString(@"DVTiOSDevice") alliOSDevices]];
  return dvtDevices[udid];
}

#pragma mark Properties

- (NSArray<FBDevice *> *)allDevices
{
  NSDictionary<NSString *, FBAMDevice *> *amDevices = [FBDeviceSet keyAMDevicesByUDID:[FBAMDevice allDevices]];

  NSMutableArray<FBDevice *> *devices = [NSMutableArray array];
  for (FBAMDevice *amDevice in amDevices.allValues) {
    FBDevice *device = [[FBDevice alloc] initWithSet:self amDevice:amDevice logger:self.logger];
    [devices addObject:device];
  }
  return [devices copy];
}

#pragma mark Predicates

+ (NSPredicate *)predicateDeviceWithUDID:(NSString *)udid
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBDevice *device, id _) {
    return [device.udid isEqualToString:udid];
  }];
}

#pragma mark Private

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
