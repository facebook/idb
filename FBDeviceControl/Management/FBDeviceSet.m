/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDeviceSet.h"

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

@interface FBDeviceSet ()

@property (nonatomic, strong, readonly) DVTDeviceManager *deviceManager;
@property (nonatomic, nullable, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBDeviceSet

#pragma mark Initializers

+ (void)initialize
{
  [FBDeviceControlFrameworkLoader initializeFrameworks];
}

+ (instancetype)defaultSetWithLogger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  DVTDeviceManager *deviceManager = [NSClassFromString(@"DVTDeviceManager") defaultDeviceManager];
  // It seems that searching for a device that does not exist will cause all available devices/simulators etc. to be cached.
  // There's probably a better way of fetching all the available devices, but this appears to work well enough.
  // This means that all the cached available devices can then be found.
  [logger.debug logFormat:@"Quering device manager for %f seconds to cache devices", FBDeviceSetDeviceManagerTickleTime];
  [deviceManager searchForDevicesWithType:nil options:@{@"id" : @"I_DONT_EXIST_AT_ALL"} timeout:FBDeviceSetDeviceManagerTickleTime error:nil];
  [logger.debug log:@"Finished querying devices to cache them"];

  return [[FBDeviceSet alloc] initWithDeviceSet:deviceManager logger:logger];
}

- (instancetype)initWithDeviceSet:(DVTDeviceManager *)deviceManager logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _deviceManager = deviceManager;
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

#pragma mark Properties

- (NSArray<FBDevice *> *)allDevices
{
  NSDictionary<NSString *, DVTiOSDevice *> *dvtDevices = [FBDeviceSet keyDVTDevicesByUDID:[NSClassFromString(@"DVTiOSDevice") alliOSDevices]];
  NSDictionary<NSString *, FBAMDevice *> *amDevices = [FBDeviceSet keyAMDevicesByUDID:[FBAMDevice allDevices]];
  if (![[NSSet setWithArray:dvtDevices.allKeys] isEqualToSet:[NSSet setWithArray:amDevices.allKeys]]) {
    [self.logger.error logFormat:
      @"DVT and MobileDevice Device UDIDs are inconsistent: DVT %@ MobileDevice %@",
      [FBCollectionInformation oneLineDescriptionFromArray:dvtDevices.allKeys],
      [FBCollectionInformation oneLineDescriptionFromArray:amDevices.allKeys]
    ];
    return @[];
  }

  NSMutableArray<FBDevice *> *devices = [NSMutableArray array];
  for (DVTiOSDevice *iOSDevice in dvtDevices.allValues) {
    FBiOSDeviceOperator *operator = [[FBiOSDeviceOperator alloc] initWithiOSDevice:iOSDevice];
    FBAMDevice *amDevice = amDevices[iOSDevice.identifier];
    if (!amDevice) {
      [self.logger.error logFormat:
        @"Expected to be able to find an AMDevice for %@. Available Devices %@",
        iOSDevice.identifier,
        [FBCollectionInformation oneLineDescriptionFromArray:amDevices.allKeys]
      ];
      continue;
    }

    FBDevice *device = [[FBDevice alloc] initWithDeviceOperator:operator dvtDevice:iOSDevice amDevce:amDevice];
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
