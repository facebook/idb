/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceSet.h"

#import <FBControlCore/FBControlCore.h>
#import <FBControlCore/FBiOSTargetSet.h>
#import <FBControlCore/FBiOSTarget.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

#import <objc/runtime.h>

#import "FBDeviceControlFrameworkLoader.h"
#import "FBDevice.h"
#import "FBDevice+Private.h"
#import "FBAMDeviceManager.h"
#import "FBAMDevice.h"
#import "FBAMDevice+Private.h"

@interface FBDeviceSet () <FBiOSTargetSetDelegate>

@end

@implementation FBDeviceSet

@synthesize allDevices = _allDevices;
@synthesize delegate = _delegate;

#pragma mark Initializers

+ (void)initialize
{
  [FBDeviceControlFrameworkLoader.new loadPrivateFrameworksOrAbort];
}

+ (nullable instancetype)defaultSetWithLogger:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error delegate:(nullable id<FBiOSTargetSetDelegate>)delegate
{
  static dispatch_once_t onceToken;
  static FBDeviceSet *deviceSet = nil;
  dispatch_once(&onceToken, ^{
    deviceSet = [[FBDeviceSet alloc] initWithLogger:logger delegate:delegate];
  });
  return deviceSet;
}

+ (nullable instancetype)defaultSetWithLogger:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error
{
  return [FBDeviceSet defaultSetWithLogger:logger error:error delegate:nil];
}

- (instancetype)initWithLogger:(id<FBControlCoreLogger>)logger delegate:(id<FBiOSTargetSetDelegate>)delegate
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _delegate = delegate;
  _logger = [logger withName:@"device_set"];
  _allDevices = @[];

  [self recalculateAllDevices];
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

- (NSArray<FBDevice *> *)query:(FBiOSTargetQuery *)query
{
  if ([query excludesAll:FBiOSTargetTypeDevice]) {
    return @[];
  }
  return (NSArray<FBDevice *> *)[query filter:_allDevices];
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

#pragma mark FBiOSTargetSet Implementation

- (NSArray<id<FBiOSTarget>> *)allTargetInfos
{
  return self.allDevices;
}

#pragma mark Private

- (void)subscribeToDeviceNotifications
{
  FBAMDeviceManager.sharedManager.delegate = self;
}

- (void)unsubscribeFromDeviceNotifications
{
  FBAMDeviceManager.sharedManager.delegate = nil;
}

- (void)recalculateAllDevices
{
  _allDevices = [[FBDeviceSet
    inflateFromDevices:FBAMDevice.allDevices existingDevices:_allDevices deviceSet:self]
    sortedArrayUsingSelector:@selector(compare:)];
}

+ (NSArray<FBDevice *> *)inflateFromDevices:(NSArray<FBAMDevice *> *)amDevices existingDevices:(NSArray<FBDevice *> *)devices deviceSet:(FBDeviceSet *)deviceSet
{
  // Inflate new Devices that have come along since last time this method was called.
  NSSet<NSString *> *existingDeviceUDIDs = [NSSet setWithArray:[devices valueForKeyPath:@"udid"]];
  NSDictionary<NSString *, FBAMDevice *> *availableDevices = [NSDictionary
    dictionaryWithObjects:amDevices
    forKeys:[amDevices valueForKeyPath:@"udid"]];

  // Calculate the new Devices that are available.
  NSMutableSet<NSString *> *devicesToInflate = [NSMutableSet setWithArray:availableDevices.allKeys];
  [devicesToInflate minusSet:existingDeviceUDIDs];

  // Calculate the Devices that are now gone.
  NSMutableSet<NSString *> *devicesToCull = [existingDeviceUDIDs mutableCopy];
  [devicesToCull minusSet:[NSSet setWithArray:availableDevices.allKeys]];

  // The hottest path, so return early to avoid doing any other work.
  if (devicesToInflate.count == 0 && devicesToCull == 0) {
    return devices;
  }

  // Cull Simulators
  id<FBControlCoreLogger> logger = deviceSet.logger;
  if (devicesToCull.count > 0) {
    [logger logFormat:@"Removing %@ from Device Set", [FBCollectionInformation oneLineDescriptionFromArray:devicesToCull.allObjects]];
    NSPredicate *predicate = [NSCompoundPredicate notPredicateWithSubpredicate:[FBiOSTargetPredicates udids:devicesToCull.allObjects]];
    devices = [devices filteredArrayUsingPredicate:predicate];
  }

  if (devicesToInflate.count > 0) {
    [logger logFormat:@"Adding %@ to Device Set", [FBCollectionInformation oneLineDescriptionFromArray:devicesToInflate.allObjects]];
    NSMutableArray<FBDevice *> *inflatedDevices = [NSMutableArray array];
    for (NSString *udid in devicesToInflate) {
      FBAMDevice *amDevice = availableDevices[udid];
      FBDevice *device = [[FBDevice alloc] initWithSet:deviceSet amDevice:amDevice logger:[logger withName:udid]];
      [inflatedDevices addObject:device];
    }
    devices = [devices arrayByAddingObjectsFromArray:inflatedDevices];
  }

  return devices;
}

#pragma mark FBiOSTargetSetDelegate Implementation

- (void)targetAdded:(id<FBiOSTargetInfo>)targetInfo inTargetSet:(id<FBiOSTargetSet>)targetSet
{
  [self.delegate targetAdded:targetInfo inTargetSet:targetSet];
}

- (void)targetRemoved:(id<FBiOSTargetInfo>)targetInfo inTargetSet:(id<FBiOSTargetSet>)targetSet
{
  [self.delegate targetRemoved:targetInfo inTargetSet:targetSet];
}

- (void)targetUpdated:(id<FBiOSTargetInfo>)targetInfo inTargetSet:(id<FBiOSTargetSet>)targetSet
{
  [self.delegate targetUpdated:targetInfo inTargetSet:targetSet];
}

@end
