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
  NSMutableArray<FBDevice *> *devices = [NSMutableArray array];
  for (DVTiOSDevice *iOSDevice in [NSClassFromString(@"DVTiOSDevice") alliOSDevices]) {
    FBiOSDeviceOperator *operator = [[FBiOSDeviceOperator alloc] initWithiOSDevice:iOSDevice];
    FBDevice *device = [[FBDevice alloc] initWithDeviceOperator:operator device:(id)iOSDevice];
    [devices addObject:device];
  }
  return [devices copy];
}

#pragma mark Predicates

+ (NSPredicate *)predicateDeviceWithUDID:(NSString *)udid
{
  return [NSPredicate predicateWithBlock:^ BOOL (FBDevice *device, id _) {
    return [device.UDID isEqualToString:udid];
  }];
}

@end
