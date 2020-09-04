/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeviceProvisioningProfileCommands.h"

#import "FBDevice.h"

@interface FBDeviceProvisioningProfileCommands ()

@property (nonatomic, weak, readonly) FBDevice *device;

@end

@implementation FBDeviceProvisioningProfileCommands

#pragma mark Public

+ (instancetype)commandsWithTarget:(FBDevice *)target
{
  return [[self alloc] initWithDevice:target];
}

- (instancetype)initWithDevice:(FBDevice *)device
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _device = device;

  return self;
}

#pragma mark FBDeviceProvisioningProfileCommands Implementation

- (FBFuture<NSArray<NSDictionary<NSString *, id> *> *> *)allProvisioningProfiles
{
  return [[self
    listProvisioningProfiles]
    onQueue:self.device.workQueue pop:^(NSArray<id> *merged) {
      id<FBDeviceCommands> device = merged[0];
      NSArray<id> *profiles = [merged subarrayWithRange:NSMakeRange(1, merged.count - 1)];
      NSMutableArray<NSDictionary<NSString *, id> *> *allProfiles = NSMutableArray.array;
      for (id profile in profiles) {
        NSDictionary<NSString *, id> *payload = CFBridgingRelease(device.calls.ProvisioningProfileCopyPayload((__bridge CFTypeRef)(profile)));
        payload = [FBCollectionOperations recursiveFilteredJSONSerializableRepresentationOfDictionary:payload];
        [allProfiles addObject:payload];
      }
      return [FBFuture futureWithResult:allProfiles];
    }];
}

- (FBFuture<NSDictionary<NSString *, id> *> *)removeProvisioningProfile:(NSString *)uuid
{
  return [[self.device
    connectToDeviceWithPurpose:@"remove_provisioning_profile"]
    onQueue:self.device.workQueue pop:^(id<FBDeviceCommands> device) {
      int status = device.calls.RemoveProvisioningProfile(device.amDeviceRef, (__bridge CFStringRef)(uuid));
      if (status != 0) {
        NSString *errorDescription = CFBridgingRelease(device.calls.ProvisioningProfileCopyErrorStringForCode(status));
        return [[FBControlCoreError
          describeFormat:@"Failed to remove profile %@: %@", uuid, errorDescription]
          failFuture];
      }
      return [FBFuture futureWithResult:@{}];
    }];
}

- (FBFuture<NSDictionary<NSString *, id> *> *)installProvisioningProfile:(NSData *)profileData
{
  return [[self.device
    connectToDeviceWithPurpose:@"install_provisioning_profile"]
    onQueue:self.device.workQueue pop:^(id<FBDeviceCommands> device) {
      MISProfileRef profile = device.calls.ProvisioningProfileCreateWithData((__bridge CFDataRef)(profileData));
      if (!profile) {
        return [[FBControlCoreError
          describeFormat:@"Could not construct profile from data %@", profileData]
          failFuture];
      }
      int status = device.calls.InstallProvisioningProfile(device.amDeviceRef, profile);
      if (status != 0) {
        NSString *errorDescription = CFBridgingRelease(device.calls.ProvisioningProfileCopyErrorStringForCode(status));
        return [[FBControlCoreError
          describeFormat:@"Failed to install profile %@: %@", profile, errorDescription]
          failFuture];
      }
      NSDictionary<NSString *, id> *payload = CFBridgingRelease(device.calls.ProvisioningProfileCopyPayload(profile));
      payload = [FBCollectionOperations recursiveFilteredJSONSerializableRepresentationOfDictionary:payload];
      if (!payload) {
        return [[FBControlCoreError
          describeFormat:@"Failed to get payload of %@", profile]
          failFuture];
      }
      return [FBFuture futureWithResult:payload];
    }];
}

#pragma mark Private

- (FBFutureContext<NSArray<id> *> *)listProvisioningProfiles
{
  return [[self.device
    connectToDeviceWithPurpose:@"list_provisioning_profiles"]
    onQueue:self.device.workQueue pend:^(id<FBDeviceCommands> device) {
      NSArray<id> *profiles = CFBridgingRelease(device.calls.CopyProvisioningProfiles(device.amDeviceRef));
      if (!profiles) {
        return [[FBControlCoreError
          describeFormat:@"Failed to copy provisioning profiles"]
          failFuture];
      }
      return [FBFuture futureWithResult:[@[device] arrayByAddingObjectsFromArray:profiles]];
    }];
}

@end
