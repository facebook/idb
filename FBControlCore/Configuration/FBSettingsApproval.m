/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSettingsApproval.h"

#import "FBControlCoreError.h"
#import "FBCollectionInformation.h"

FBSettingsApprovalService const FBSettingsApprovalServiceContacts = @"contacts";
FBSettingsApprovalService const FBSettingsApprovalServicePhotos = @"photos";
FBSettingsApprovalService const FBSettingsApprovalServiceCamera = @"camera";
FBSettingsApprovalService const FBSettingsApprovalServiceLocation = @"location";
FBSettingsApprovalService const FBSettingsApprovalServiceMicrophone = @"microphone";
FBSettingsApprovalService const FBSettingsApprovalServiceUrl = @"url";
FBSettingsApprovalService const FBSettingsApprovalServiceNotification = @"notification";

@implementation FBSettingsApproval

#pragma mark Initializers

+ (instancetype)approvalWithBundleIDs:(NSArray<NSString *> *)bundleIDs services:(NSArray<FBSettingsApprovalService> *)services
{
  return [[self alloc] initWithBundleIDs:bundleIDs services:services];
}

- (instancetype)initWithBundleIDs:(NSArray<NSString *> *)bundleIDs services:(NSArray<FBSettingsApprovalService> *)services
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _bundleIDs = bundleIDs;
  _services = services;

  return self;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBSettingsApproval *)approval
{
  if (![approval isKindOfClass:FBSettingsApproval.class]) {
    return NO;
  }
  return [self.bundleIDs isEqualToArray:approval.bundleIDs] &&
         [self.services isEqualToArray:approval.services];
}

- (NSUInteger)hash
{
  return self.bundleIDs.hash ^ self.services.hash;
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone
{
  return self;
}

#pragma mark JSON

static NSString *const KeyBundleIDs = @"bundle_ids";
static NSString *const KeyServices = @"services";

+ (instancetype)inflateFromJSON:(NSDictionary<NSString *, NSArray<NSString *> *> *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSArray.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a Dictionary<String, Array<String>>", json]
      fail:error];
  }
  NSArray<NSString *> *bundleIDs = json[KeyBundleIDs];
  if (![FBCollectionInformation isArrayHeterogeneous:bundleIDs withClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a Array<String> for %@", bundleIDs, KeyBundleIDs]
      fail:error];
  }
  NSArray<FBSettingsApprovalService> *approvals = json[KeyServices];
  if (![FBCollectionInformation isArrayHeterogeneous:approvals withClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a Array<String> for %@", approvals, KeyServices]
      fail:error];
  }
  return [[self alloc] initWithBundleIDs:bundleIDs services:approvals];
}

- (id)jsonSerializableRepresentation
{
  return @{
    KeyBundleIDs: self.bundleIDs,
    KeyServices: self.services,
  };
}

@end
