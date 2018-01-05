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

#import <IDEiOSSupportCore/DVTiOSDevice.h>

#import <FBControlCore/FBControlCore.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

#import <objc/runtime.h>

#import "FBDeviceControlFrameworkLoader.h"
#import "FBDevice.h"
#import "FBDevice+Private.h"
#import "FBAMDevice.h"
#import "FBAMDevice+Private.h"
#import "FBDeviceInflationStrategy.h"

@implementation FBDeviceSet

@synthesize allDevices = _allDevices;

#pragma mark Initializers

+ (void)initialize
{
  [FBDeviceControlFrameworkLoader.essentialFrameworks loadPrivateFrameworksOrAbort];
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
  [self recalculateAllDevices];
  [self subscribeToDeviceNotifications];

  return self;
}

- (void)dealloc
{
  [self unsubscribeFromDeviceNotifications];
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
  return [FBDeviceInflationStrategy strategyForSet:self];
}

- (void)subscribeToDeviceNotifications
{
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(deviceAttachedNotification:) name:FBAMDeviceNotificationNameDeviceAttached object:nil];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(deviceDetachedNotification:) name:FBAMDeviceNotificationNameDeviceDetached object:nil];
}

- (void)unsubscribeFromDeviceNotifications
{
  [NSNotificationCenter.defaultCenter removeObserver:self name:FBAMDeviceNotificationNameDeviceAttached object:nil];
  [NSNotificationCenter.defaultCenter removeObserver:self name:FBAMDeviceNotificationNameDeviceDetached object:nil];
}

- (void)deviceAttachedNotification:(NSNotification *)notification
{
  [self recalculateAllDevices];
}

- (void)deviceDetachedNotification:(NSNotification *)notification
{
  [self recalculateAllDevices];
}

- (void)recalculateAllDevices
{
  _allDevices = [[self.inflationStrategy
    inflateFromDevices:FBAMDevice.allDevices existingDevices:_allDevices]
    sortedArrayUsingSelector:@selector(compare:)];
}

@end
