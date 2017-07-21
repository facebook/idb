/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBBundleDescriptor.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The Installed Type of the Application.
 */
typedef NS_ENUM(NSUInteger, FBApplicationInstallType) {
  FBApplicationInstallTypeUnknown = 0, /** The Application Type is Unknown */
  FBApplicationInstallTypeSystem = 1, /** The Application Type is part of the Operating System */
  FBApplicationInstallTypeUser = 2, /** The Application Type is installable by the User */
  FBApplicationInstallTypeMac = 3, /** The Application Type is part of macOS */
};

/**
 String Representations of the Installed Type.
 */
typedef NSString *FBApplicationInstallTypeString NS_STRING_ENUM;
extern FBApplicationInstallTypeString const FBApplicationInstallTypeStringUnknown;
extern FBApplicationInstallTypeString const FBApplicationInstallTypeStringSystem;
extern FBApplicationInstallTypeString const FBApplicationInstallTypeStringUser;
extern FBApplicationInstallTypeString const FBApplicationInstallTypeStringMac;

/**
 Keys from UserInfo about Applications
 */
typedef NSString *FBApplicationInstallInfoKey NS_EXTENSIBLE_STRING_ENUM;
extern FBApplicationInstallInfoKey const FBApplicationInstallInfoKeyApplicationType;
extern FBApplicationInstallInfoKey const FBApplicationInstallInfoKeyPath;

@class FBBinaryDescriptor;

/**
 A Bundle Descriptor specialized to Applications
 */
@interface FBApplicationBundle : FBBundleDescriptor

/**
 Initializes a FBApplicationBundle.

 @param name the name of the application
 @param path the path of the application
 @param bundleID the bundle id of the application
 @param installType the InstallType of the application.
 @returns a FBApplicationBundle instance.
 */
- (instancetype)initWithName:(NSString *)name path:(NSString *)path bundleID:(NSString *)bundleID binary:(nullable FBBinaryDescriptor *)binary installType:(FBApplicationInstallType)installType;

/**
 Constructs a FBApplicationBundle for the a User Application at the given path

 @param path the path of the applocation to construct.
 @param error an error out.
 @returns a FBApplicationBundle instance if one could be constructed, nil otherwise.
 */
+ (nullable instancetype)userApplicationWithPath:(NSString *)path error:(NSError **)error;

/**
 Constructs a FBApplicationBundle for the an Application.

 @param name the name of the application
 @param path the path of the application
 @param bundleID the bundle id of the application
 @param installType the install type of the application
 @returns a FBApplicationBundle instance.
 */
+ (instancetype)applicationWithName:(NSString *)name path:(NSString *)path bundleID:(NSString *)bundleID installType:(FBApplicationInstallType)installType;

/**
 Constructs a FBApplicationBundle for the Application at the given path.

 @param path the path of the applocation to construct.
 @param installType the InstallType of the application.
 @param error an error out.
 @returns a FBApplicationBundle instance if one could be constructed, nil otherwise.
 */
+ (nullable instancetype)applicationWithPath:(NSString *)path installType:(FBApplicationInstallType)installType error:(NSError **)error;

/**
 Constructs a FBApplicationBundle for the Application at the given path.

 @param path the path of the applocation to construct.
 @param installTypeString a string representation of the InstallType of the application.
 @param error an error out.
 @returns a FBApplicationBundle instance if one could be constructed, nil otherwise.
 */
+ (nullable instancetype)applicationWithPath:(NSString *)path installTypeString:(nullable NSString *)installTypeString error:(NSError **)error;

/**
 The Install Type of the Application.
 */
@property (nonatomic, assign, readonly) FBApplicationInstallType installType;

/**
 Returns a String Represnting the Application Install Type.
 */
+ (FBApplicationInstallTypeString)stringFromApplicationInstallType:(FBApplicationInstallType)installType;

/**
 Returns the FBApplicationInstallType from the string representation.

 @param installTypeString install type as a string
 */
+ (FBApplicationInstallType)installTypeFromString:(nullable FBApplicationInstallTypeString)installTypeString;

/**
 Finds or Extracts an Application if it is determined to be an IPA.
 If the Path is a .app, it will be returned unchanged.

 @param path the path of the .app or .ipa
 @param extractPathOut an outparam for the path where the Application is extracted.
 @param error any error that occurred in fetching the application.
 @return the path if successful, NO otherwise.
 */
+ (nullable NSString *)findOrExtractApplicationAtPath:(NSString *)path extractPathOut:(NSURL *_Nullable* _Nullable)extractPathOut error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
