/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBManagedConfigClient.h"

#import "FBAMDServiceConnection.h"

NSString *const FBManagedConfigService = @"com.apple.mobile.MCInstall";

@interface FBManagedConfigClient ()

@property (nonatomic, strong, readonly) FBAMDServiceConnection *connection;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBManagedConfigClient

#pragma mark Initializers

+ (instancetype)managedConfigClientWithConnection:(FBAMDServiceConnection *)connection logger:(id<FBControlCoreLogger>)logger
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.FBDeviceControl.managed_config", DISPATCH_QUEUE_SERIAL);
  return [[self alloc] initWithConnection:connection queue:queue logger:logger];
}

- (instancetype)initWithConnection:(FBAMDServiceConnection *)connection queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _connection = connection;
  _queue = queue;
  _logger = logger;

  return self;
}

#pragma mark Public Methods

- (FBFuture<NSDictionary<NSString *, id> *> *)getCloudConfiguration
{
  return [FBFuture
    onQueue:self.queue resolveValue:^ NSDictionary<NSString *, id> * (NSError **error) {
      NSDictionary<NSString *, id> *result = [self.connection sendAndReceiveMessage:@{@"RequestType": @"GetCloudConfiguration"} error:error];
      if (!result) {
        return nil;
      }
      return [FBCollectionOperations recursiveFilteredJSONSerializableRepresentationOfDictionary:result];
    }];
}

- (FBFuture<NSNull *> *)changeWallpaperWithName:(FBWallpaperName)name data:(NSData *)data
{
  NSNumber *whereNumber = FBManagedConfigClient.wallpaperWhereForName[name];
  if (!whereNumber) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a valid Wallpaper Name", name]
      failFuture];
  }
  return [self changeSettings:@[
    @{@"Item": @"Wallpaper", @"Image": data, @"Where": whereNumber}
  ]];
}

static NSString * const OrderedIdentifiers = @"OrderedIdentifiers";
static NSString * const ProfileMetadata = @"ProfileMetadata";
static NSString * const PayloadUUID = @"PayloadUUID";
static NSString * const PayloadVersion = @"PayloadVersion";

- (FBFuture<NSArray<NSString *> *> *)getProfileList
{
  return [FBFuture
    onQueue:self.queue resolveValue:^ NSArray<NSString *> * (NSError **error) {
      NSDictionary<NSString *, id> *result = [self.connection sendAndReceiveMessage:@{@"RequestType": @"GetProfileList"} error:error];
      if (!result) {
        return nil;
      }
      NSArray<NSString *> *orderedIdentifiers = result[OrderedIdentifiers];
      if (![FBCollectionInformation isArrayHeterogeneous:orderedIdentifiers withClass:NSString.class]) {
        return [[FBControlCoreError
          describeFormat:@"%@ is not an Array<String>", OrderedIdentifiers]
          fail:error];
      }
      return orderedIdentifiers;
  }];
}

- (FBFuture<NSNull *> *)installProfile:(NSData *)payload
{
  return [FBFuture
    onQueue:self.queue resolveValue:^ NSDictionary<NSString *, id> * (NSError **error) {
      NSDictionary<NSString *, id> *result = [self.connection sendAndReceiveMessage:@{@"RequestType": @"InstallProfile", @"Payload": payload} error:error];
      if (!result) {
        return nil;
      }
      return [FBCollectionOperations recursiveFilteredJSONSerializableRepresentationOfDictionary:result];
  }];
}

- (FBFuture<NSNull *> *)removeProfile:(NSString *)profileName
{
  return [FBFuture
    onQueue:self.queue resolveValue:^ NSNull * (NSError **error) {
      NSDictionary<NSString *, id> *result = [self.connection sendAndReceiveMessage:@{@"RequestType": @"GetProfileList"} error:error];
      if (!result) {
        return nil;
      }
      NSDictionary<NSString *, id> *profileMetadata = result[ProfileMetadata][profileName];
      if (!profileMetadata) {
        return [[FBControlCoreError
          describeFormat:@"%@ is not one of %@", profileName, [FBCollectionInformation oneLineDescriptionFromArray:result[OrderedIdentifiers]]]
          fail:error];
      }
      NSDictionary<NSString *, id> *profileIdentifier = @{
        @"PayloadType": @"Configuration",
        @"PayloadIdentifier": profileName,
        PayloadUUID: profileMetadata[PayloadUUID],
        PayloadVersion: profileMetadata[PayloadVersion]
      };
      NSData *payload = [NSPropertyListSerialization dataWithPropertyList:profileIdentifier format:0xc8 options:0 error:error];
      if (!payload) {
        return nil;
      }
      result = [self.connection sendAndReceiveMessage:@{@"RequestType": @"RemoveProfile", @"ProfileIdentifier": payload} error:error];
      if (!result) {
        return nil;
      }
      NSString *status = result[@"Status"];
      if ([status isEqualToString:@"Error"]) {
        return [[FBControlCoreError
          describeFormat:@"Status is Error: %@", result]
          fail:error];
      }
      return NSNull.null;
    }];
}

#pragma mark Private Methods

- (FBFuture<NSNull *> *)changeSettings:(NSArray<NSDictionary<NSString *, id> *> *)settings
{
  return [FBFuture
    onQueue:self.queue resolveValue:^ NSNull * (NSError **error) {
      NSDictionary<NSString *, id> *result = [self.connection sendAndReceiveMessage:@{@"RequestType": @"Settings", @"Settings": settings} error:error];
      if (!result) {
        return nil;
      }
      return NSNull.null;
    }];
}

+ (NSDictionary<FBWallpaperName, NSNumber *> *)wallpaperWhereForName
{
  static dispatch_once_t onceToken;
  static NSDictionary<FBWallpaperName, NSNumber *> *value;
  dispatch_once(&onceToken, ^{
    value = @{FBWallpaperNameHomescreen: @0, FBWallpaperNameLockscreen: @1};
  });
  return value;
}

@end
