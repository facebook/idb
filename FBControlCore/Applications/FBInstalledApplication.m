/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBInstalledApplication.h"

#import "FBBundleDescriptor.h"

FBApplicationInstallTypeString const FBApplicationInstallTypeStringUnknown = @"unknown";
FBApplicationInstallTypeString const FBApplicationInstallTypeStringSystem = @"system";
FBApplicationInstallTypeString const FBApplicationInstallTypeStringMac = @"mac";
FBApplicationInstallTypeString const FBApplicationInstallTypeStringUser = @"user";
FBApplicationInstallTypeString const FBApplicationInstallTypeStringUserEnterprise = @"user_enterprise";
FBApplicationInstallTypeString const FBApplicationInstallTypeStringUserDevelopment = @"user_development";

FBApplicationInstallInfoKey const FBApplicationInstallInfoKeyApplicationType = @"ApplicationType";
FBApplicationInstallInfoKey const FBApplicationInstallInfoKeyBundleIdentifier = @"CFBundleIdentifier";
FBApplicationInstallInfoKey const FBApplicationInstallInfoKeyBundleName = @"CFBundleName";
FBApplicationInstallInfoKey const FBApplicationInstallInfoKeyPath = @"Path";
FBApplicationInstallInfoKey const FBApplicationInstallInfoKeySignerIdentity = @"SignerIdentity";

@implementation FBInstalledApplication

#pragma mark Initializers

+ (instancetype)installedApplicationWithBundle:(FBBundleDescriptor *)bundle installType:(FBApplicationInstallType)installType
{
  return [self installedApplicationWithBundle:bundle installType:installType dataContainer:nil];
}

+ (instancetype)installedApplicationWithBundle:(FBBundleDescriptor *)bundle installType:(FBApplicationInstallType)installType dataContainer:(NSString *)dataContainer
{
  return [[self alloc] initWithBundle:bundle installType:installType dataContainer:dataContainer];
}

- (instancetype)initWithBundle:(FBBundleDescriptor *)bundle installType:(FBApplicationInstallType)installType dataContainer:(NSString *)dataContainer
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _bundle = bundle;
  _installType = installType;
  _dataContainer = dataContainer;

  return self;
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return self.bundle.hash ^ self.installType;
}

- (BOOL)isEqual:(FBInstalledApplication *)object
{
  if (![object isKindOfClass:FBInstalledApplication.class]) {
    return NO;
  }
  return [self.bundle isEqual:object.bundle]
      && self.installType == object.installType
      && (self.dataContainer == object.dataContainer || [self.dataContainer isEqualToString:object.dataContainer]);
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Bundle %@ | Install Type %@ | Container %@",
    self.bundle.description,
    [FBInstalledApplication stringFromApplicationInstallType:self.installType],
    self.dataContainer
  ];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

#pragma mark JSON Serialization

static NSString *const KeyBundle = @"bundle";
static NSString *const KeyInstallType = @"install_type";
static NSString *const KeyDataContainer = @"data_container";

- (id)jsonSerializableRepresentation
{
  return @{
    KeyBundle: self.bundle.jsonSerializableRepresentation,
    KeyInstallType: [FBInstalledApplication stringFromApplicationInstallType:self.installType],
    KeyDataContainer: self.dataContainer ?: NSNull.null,
  };
}

#pragma mark Install Type

+ (FBApplicationInstallTypeString)stringFromApplicationInstallType:(FBApplicationInstallType)installType
{
  switch (installType) {
    case FBApplicationInstallTypeUser:
      return FBApplicationInstallTypeStringUser;
    case FBApplicationInstallTypeUserDevelopment:
      return FBApplicationInstallTypeStringUserDevelopment;
    case FBApplicationInstallTypeUserEnterprise:
      return FBApplicationInstallTypeStringUserEnterprise;
    case FBApplicationInstallTypeSystem:
      return FBApplicationInstallTypeStringSystem;
    case FBApplicationInstallTypeMac:
      return FBApplicationInstallTypeStringMac;
    default:
      return FBApplicationInstallTypeStringUnknown;
  }
}

+ (FBApplicationInstallType)installTypeFromString:(nullable FBApplicationInstallTypeString)installTypeString signerIdentity:(nullable NSString *)signerIdentity
{
  if (!installTypeString) {
    return FBApplicationInstallTypeUnknown;
  }
  installTypeString = [installTypeString lowercaseString];
  if ([installTypeString isEqualToString:FBApplicationInstallTypeStringSystem]) {
    return FBApplicationInstallTypeSystem;
  }
  if ([installTypeString isEqualToString:FBApplicationInstallTypeStringUser]) {
    if ([signerIdentity containsString:@"iPhone Distribution"]) {
      return FBApplicationInstallTypeUserEnterprise;
    } else if ([signerIdentity containsString:@"iPhone Developer"] || [signerIdentity containsString:@"Apple Development"]) {
      return FBApplicationInstallTypeUserDevelopment;
    }
    return FBApplicationInstallTypeUser;
  }
  if ([installTypeString isEqualToString:FBApplicationInstallTypeStringMac]) {
    return FBApplicationInstallTypeMac;
  }
  return FBApplicationInstallTypeUnknown;
}

@end
