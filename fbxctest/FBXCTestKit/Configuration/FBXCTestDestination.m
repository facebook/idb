/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestDestination.h"

#import <XCTestBootstrap/XCTestBootstrap.h>

@implementation FBXCTestDestination

- (NSString *)xctestPath
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  // References are immutable.
  return self;
}

#pragma mark JSON

static NSString *KeyPlatform = @"platform";
static NSString *KeyPlatformiOSSimulator = @"iphonesimulator";
static NSString *KeyPlatformMacOS = @"macos";

+ (nullable instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a Dictionary<String, Any>", json]
      fail:error];
  }
  NSString *platform = json[KeyPlatform];
  if (![platform isKindOfClass:NSString.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a String for %@", platform, KeyPlatform]
      fail:error];
  }
  if ([platform isEqualToString:KeyPlatformiOSSimulator]) {
    return [FBXCTestDestinationiPhoneSimulator inflateFromJSON:json error:error];
  }
  if ([platform isEqualToString:KeyPlatformMacOS]) {
    return [FBXCTestDestinationMacOSX inflateFromJSON:json error:error];
  }
  return [[FBXCTestError
    describeFormat:@"%@ is not %@ %@ for %@", platform, KeyPlatformiOSSimulator, KeyPlatformMacOS, KeyPlatform]
    fail:error];
}

- (id)jsonSerializableRepresentation
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

@end

@implementation FBXCTestDestinationMacOSX

#pragma mark NSObject

- (BOOL)isEqual:(FBXCTestDestinationiPhoneSimulator *)object
{
  return [object isKindOfClass:self.class];
}

- (NSUInteger)hash
{
  return KeyPlatformiOSSimulator.hash;
}

#pragma mark JSON

+ (nullable instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  return [[FBXCTestDestinationMacOSX alloc] init];
}

- (id)jsonSerializableRepresentation
{
  return @{
    KeyPlatform: KeyPlatformMacOS,
  };
}


@end

@implementation FBXCTestDestinationiPhoneSimulator

- (instancetype)initWithModel:(nullable FBDeviceModel)model version:(nullable FBOSVersionName)version
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _model = model;
  _version = version;

  return self;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBXCTestDestinationiPhoneSimulator *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return (self.model == object.model || [self.model isEqualToString:object.model])
      && (self.version == object.version || [self.version isEqualToString:object.version]);
}

- (NSUInteger)hash
{
  return self.model.hash ^ self.version.hash ^ KeyPlatformiOSSimulator.hash;
}

#pragma mark JSON

static NSString *const KeyModel = @"model";
static NSString *const KeyOSVersion = @"os";

+ (nullable instancetype)inflateFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  FBDeviceModel model = [FBCollectionOperations nullableValueForDictionary:json key:KeyModel];
  if (model && ![model isKindOfClass:NSString.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a String? for %@", model, KeyModel]
      fail:error];
  }
  FBOSVersionName os = [FBCollectionOperations nullableValueForDictionary:json key:KeyOSVersion];
  if (os && ![os isKindOfClass:NSString.class]) {
    return [[FBXCTestError
      describeFormat:@"%@ is not a String? for %@", model, KeyOSVersion]
      fail:error];
  }
  return [[FBXCTestDestinationiPhoneSimulator alloc] initWithModel:model version:os];
}

- (id)jsonSerializableRepresentation
{
  return @{
    KeyPlatform: KeyPlatformiOSSimulator,
    KeyModel: self.model ?: NSNull.null,
    KeyOSVersion: self.version ?: NSNull.null,
  };
}

@end
