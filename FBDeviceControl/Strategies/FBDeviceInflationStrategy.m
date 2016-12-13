/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBDeviceInflationStrategy.h"

#import <FBControlCore/FBControlCore.h>

#import "FBDevice.h"
#import "FBDevice+Private.h"
#import "FBDeviceSet.h"
#import "FBDeviceSet+Private.h"

@interface FBDeviceInflationStrategy ()

@property (nonatomic, weak, readonly) FBDeviceSet *set;

@end

@implementation FBDeviceInflationStrategy

+ (instancetype)forSet:(FBDeviceSet *)set
{
  return [[self alloc] initWithSet:set];
}

- (instancetype)initWithSet:(FBDeviceSet *)set
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _set = set;
  return self;
}

- (NSArray<FBDevice *> *)inflateFromDevices:(NSArray<FBAMDevice *> *)amDevices existingDevices:(NSArray<FBDevice *> *)devices
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
  if (devicesToCull.count > 0) {
    NSPredicate *predicate = [NSCompoundPredicate notPredicateWithSubpredicate:[FBiOSTargetPredicates udids:devicesToCull.allObjects]];
    devices = [devices filteredArrayUsingPredicate:predicate];
  }

  if (devicesToInflate.count > 0) {
    NSMutableArray<FBDevice *> *inflatedDevices = [NSMutableArray array];
    for (NSString *udid in devicesToInflate) {
      FBAMDevice *amDevice = availableDevices[udid];
      FBDevice *device = [[FBDevice alloc] initWithSet:self.set amDevice:amDevice logger:self.set.logger];
      [inflatedDevices addObject:device];
    }
    devices = [devices arrayByAddingObjectsFromArray:inflatedDevices];
  }

  return devices;
}

@end
