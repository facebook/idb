/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceSet.h"

#import <FBControlCore/FBControlCore.h>
#import <FBControlCore/FBiOSTargetSet.h>
#import <FBControlCore/FBiOSTarget.h>

#import <objc/runtime.h>

#import "FBAMDevice+Private.h"
#import "FBAMDevice.h"
#import "FBAMDeviceManager.h"
#import "FBAMRestorableDevice.h"
#import "FBAMRestorableDeviceManager.h"
#import "FBDevice+Private.h"
#import "FBDevice.h"
#import "FBDeviceControlFrameworkLoader.h"
#import "FBDeviceStorage.h"

@interface FBDeviceSet () <FBiOSTargetSetDelegate>

@property (nonatomic, strong, readonly) FBAMDeviceManager *amDeviceManager;
@property (nonatomic, strong, readonly) FBAMRestorableDeviceManager *restorableDeviceManager;
@property (nonatomic, strong, readonly) FBDeviceStorage<FBDevice *> *storage;

@end

@implementation FBDeviceSet

@synthesize delegate = _delegate;

#pragma mark Initializers

+ (void)initialize
{
  [FBDeviceControlFrameworkLoader.new loadPrivateFrameworksOrAbort];
}

+ (nullable instancetype)setWithLogger:(id<FBControlCoreLogger>)logger delegate:(id<FBiOSTargetSetDelegate>)delegate ecidFilter:(NSString *)ecidFilter error:(NSError **)error
{
  dispatch_queue_t workQueue = dispatch_get_main_queue();
  dispatch_queue_t asyncQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
  return [FBDeviceSet setWithWorkQueue:workQueue asyncQueue:asyncQueue logger:logger delegate:delegate ecidFilter:ecidFilter error:error];
}

+ (nullable instancetype)setWithWorkQueue:(dispatch_queue_t)workQueue asyncQueue:(dispatch_queue_t)asyncQueue logger:(id<FBControlCoreLogger>)logger delegate:(id<FBiOSTargetSetDelegate>)delegate ecidFilter:(NSString *)ecidFilter error:(NSError **)error
{
  AMDCalls calls = FBDeviceControlFrameworkLoader.amDeviceCalls;
  FBAMDeviceManager *amDeviceManager = [[FBAMDeviceManager alloc] initWithCalls:calls workQueue:workQueue asyncQueue:asyncQueue ecidFilter:ecidFilter logger:logger];
  FBAMRestorableDeviceManager *restorableDeviceManager = [[FBAMRestorableDeviceManager alloc] initWithCalls:calls workQueue:workQueue asyncQueue:asyncQueue ecidFilter:ecidFilter logger:logger];
  FBDeviceSet *deviceSet = [[FBDeviceSet alloc] initWithAMDeviceManager:amDeviceManager restorableDeviceManager:restorableDeviceManager logger:logger delegate:delegate];
  if (![amDeviceManager startListeningWithError:error]) {
    return nil;
  }
  if (![restorableDeviceManager startListeningWithError:error]) {
    return nil;
  }
  return deviceSet;
}

- (instancetype)initWithAMDeviceManager:(FBAMDeviceManager *)amDeviceManager restorableDeviceManager:(FBAMRestorableDeviceManager *)restorableDeviceManager logger:(id<FBControlCoreLogger>)logger delegate:(id<FBiOSTargetSetDelegate>)delegate
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _amDeviceManager = amDeviceManager;
  _restorableDeviceManager = restorableDeviceManager;
  _delegate = delegate;
  _logger = logger;
  _storage = [[FBDeviceStorage alloc] initWithLogger:logger];

  [self subscribeToDeviceNotifications];

  return self;
}

- (void)dealloc
{
  [self unsubscribeFromDeviceNotifications];
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"FBDeviceSet: %@", [FBCollectionInformation oneLineDescriptionFromArray:self.allDevices]];
}

#pragma mark Querying

- (id<FBiOSTargetInfo>)targetWithUDID:(NSString *)udid
{
  return [self deviceWithUDID:udid];
}

- (FBDevice *)deviceWithUDID:(NSString *)udid
{
  return [[self.allDevices filteredArrayUsingPredicate:FBiOSTargetPredicateForUDID(udid)] firstObject];
}

#pragma mark FBiOSTargetSet Implementation

- (NSArray<id<FBiOSTarget>> *)allTargetInfos
{
  return self.allDevices;
}

#pragma mark Private

- (void)subscribeToDeviceNotifications
{
  self.amDeviceManager.delegate = self;
  self.restorableDeviceManager.delegate = self;
  for (FBAMDevice *amDevice in self.amDeviceManager.currentDeviceList) {
    [self targetAdded:amDevice inTargetSet:self.amDeviceManager];
  }
  for (FBAMRestorableDevice *restorableDevice in self.restorableDeviceManager.currentDeviceList) {
    [self targetAdded:restorableDevice inTargetSet:self.restorableDeviceManager];
  }
}

- (void)unsubscribeFromDeviceNotifications
{
  self.amDeviceManager.delegate = nil;
  self.restorableDeviceManager.delegate = nil;
}

- (void)amDeviceAdded:(FBAMDevice *)amDevice
{
  FBDevice *device = [self.storage deviceForKey:amDevice.uniqueIdentifier];
  if (device) {
    device.amDevice = amDevice;
  } else {
    device = [[FBDevice alloc] initWithSet:self amDevice:amDevice restorableDevice:nil logger:self.logger];
    [self.storage deviceAttached:device forKey:amDevice.uniqueIdentifier];
  }
  [self.delegate targetAdded:device inTargetSet:self];
}

- (void)amDeviceRemoved:(FBAMDevice *)amDevice
{
  FBDevice *device = [self.storage deviceForKey:amDevice.uniqueIdentifier];
  if (!device) {
    [self.logger logFormat:@"%@ was removed, but there's no active device for it", amDevice];
    return;
  }
  device.amDevice = NULL;
  if (device.amDevice || device.restorableDevice) {
    [self.delegate targetUpdated:device inTargetSet:self];
  } else {
    [self.storage deviceDetachedForKey:amDevice.uniqueIdentifier];
    [self.delegate targetRemoved:device inTargetSet:self];
  }
}

- (void)restorableDeviceAdded:(FBAMRestorableDevice *)restorableDevice
{
  FBDevice *device = [self.storage deviceForKey:restorableDevice.uniqueIdentifier];
  if (device) {
    device.restorableDevice = restorableDevice;
  } else {
    device = [[FBDevice alloc] initWithSet:self amDevice:nil restorableDevice:restorableDevice logger:self.logger];
    [self.storage deviceAttached:device forKey:restorableDevice.uniqueIdentifier];
  }
  [self.delegate targetAdded:device inTargetSet:self];
}

- (void)restorableDeviceRemoved:(FBAMRestorableDevice *)restorableDevice
{
  FBDevice *device = [self.storage deviceForKey:restorableDevice.uniqueIdentifier];
  if (!device) {
    [self.logger logFormat:@"%@ was removed, but there's no active device for it", restorableDevice];
    return;
  }
  device.restorableDevice = NULL;
  if (device.amDevice || device.restorableDevice) {
    [self.delegate targetUpdated:device inTargetSet:self];
  } else {
    [self.storage deviceDetachedForKey:restorableDevice.uniqueIdentifier];
    [self.delegate targetRemoved:device inTargetSet:self];
  }
}

#pragma mark Properties

- (NSArray<FBDevice *> *)allDevices
{
  return [self.storage.attached.allValues sortedArrayUsingSelector:@selector(uniqueIdentifier)];
}

#pragma mark FBiOSTargetSetDelegate Implementation

- (void)targetAdded:(id<FBiOSTargetInfo>)targetInfo inTargetSet:(id<FBiOSTargetSet>)targetSet
{
  if ([targetInfo isKindOfClass:FBAMDevice.class]) {
    [self amDeviceAdded:(FBAMDevice *) targetInfo];
  } else if ([targetInfo isKindOfClass:FBAMRestorableDevice.class]) {
    [self restorableDeviceAdded:(FBAMRestorableDevice *) targetInfo];
  } else {
    [self.logger logFormat:@"Ignoring %@ as it is not a valid target type", targetInfo];
  }
}

- (void)targetRemoved:(id<FBiOSTargetInfo>)targetInfo inTargetSet:(id<FBiOSTargetSet>)targetSet
{
  if ([targetInfo isKindOfClass:FBAMDevice.class]) {
    [self amDeviceRemoved:(FBAMDevice *) targetInfo];
  } else if ([targetInfo isKindOfClass:FBAMRestorableDevice.class]) {
    [self restorableDeviceRemoved:(FBAMRestorableDevice *) targetInfo];
  } else {
    [self.logger logFormat:@"Ignoring %@ as it is not a valid target type", targetInfo];
  }
}

- (void)targetUpdated:(id<FBiOSTargetInfo>)targetInfo inTargetSet:(id<FBiOSTargetSet>)targetSet
{
  FBDevice *device = [self.storage deviceForKey:targetInfo.uniqueIdentifier];
  if (device && [targetInfo isKindOfClass:FBAMDevice.class]) {
    device.amDevice = (FBAMDevice *) targetInfo;
  } else if (device && [targetInfo isKindOfClass:FBAMRestorableDevice.class]) {
    device.restorableDevice = (FBAMRestorableDevice *) targetInfo;
  } else {
    NSAssert(NO, @"No existing device to update for %@", targetInfo);
  }
  [self.delegate targetUpdated:device inTargetSet:self];
}

@end
