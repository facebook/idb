/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

@class DVTExtendedPlatformInfo, DVTFilePath, DVTPlatformFamily, DVTVersion, NSArray, NSDictionary, NSHashTable, NSSet, NSString;

@interface DVTPlatform : NSObject <NSCopying>
{
    NSString *_identifier;
    NSArray *_alternateNames;
    NSString *_name;
    DVTPlatformFamily *_family;
    DVTVersion *_minimumSDKVersion;
    NSString *_platformDirectoryName;
    DVTFilePath *_platformPath;
    NSString *_userDescription;
    BOOL _isDeploymentPlatform;
    DVTFilePath *_iconPath;
    NSDictionary *_propertyListDictionary;
    NSDictionary *_internalPropertyListDictionary;
    NSHashTable *_SDKs;
    NSDictionary *_deviceProperties;
    NSString *_platformVersion;
}

+ (id)_preferredArchitectureForPlatformWithIdentifier:(id)arg1;
+ (id)extraPlatformFolders;
+ (id)defaultPlatform;
+ (BOOL)loadAllPlatformsReturningError:(id *)arg1;
+ (void)_loadPlatformAtPath:(id)arg1;
+ (id)_propertyDictionaryForPlatformAtPath:(id)arg1;
+ (id)allPlatforms;
+ (void)registerPlatform:(id)arg1;
+ (id)platformForPath:(id)arg1;
+ (void)_mapPlatformPath:(id)arg1 toPlatform:(id)arg2;
+ (id)_allPlatformsByIdentifierValues;
+ (id)platformForIdentifier:(id)arg1;
+ (void)_mapPlatformIdentifier:(id)arg1 toPlatform:(id)arg2;
+ (id)platformForUserDescription:(id)arg1;
+ (id)platformForName:(id)arg1;
+ (void)_mapPlatformName:(id)arg1 toPlatform:(id)arg2 isAlias:(BOOL)arg3;
+ (void)initialize;
@property(readonly, copy) NSString *platformVersion; // @synthesize platformVersion=_platformVersion;
@property(readonly, copy) NSDictionary *deviceProperties; // @synthesize deviceProperties=_deviceProperties;
@property(readonly) DVTFilePath *iconPath; // @synthesize iconPath=_iconPath;
@property(readonly) BOOL isDeploymentPlatform; // @synthesize isDeploymentPlatform=_isDeploymentPlatform;
@property(readonly, copy) NSString *userDescription; // @synthesize userDescription=_userDescription;
@property(readonly) DVTFilePath *platformPath; // @synthesize platformPath=_platformPath;
@property(readonly, copy) NSString *platformDirectoryName; // @synthesize platformDirectoryName=_platformDirectoryName;
@property(readonly) DVTVersion *minimumSDKVersion; // @synthesize minimumSDKVersion=_minimumSDKVersion;
@property(readonly) DVTPlatformFamily *family; // @synthesize family=_family;
@property(readonly, copy) NSString *name; // @synthesize name=_name;
@property(readonly, copy) NSArray *alternateNames; // @synthesize alternateNames=_alternateNames;
@property(readonly, copy) NSString *identifier; // @synthesize identifier=_identifier;

- (id)copyWithZone:(struct _NSZone *)arg1;
- (unsigned long long)hash;
- (BOOL)isEqual:(id)arg1;
- (id)description;
@property(readonly, copy) NSSet *SDKs;
- (void)addSDK:(id)arg1;
- (id)internalPropertyListDictionary;
- (id)propertyListDictionary;
- (id)initWithPath:(id)arg1;
- (id)initWithPropertyListDictionary:(id)arg1 path:(id)arg2;
@property(readonly) DVTExtendedPlatformInfo *dvt_extendedInfo;

@end

