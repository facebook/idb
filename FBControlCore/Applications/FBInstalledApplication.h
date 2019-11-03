/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBJSONConversion.h>

NS_ASSUME_NONNULL_BEGIN

@class FBBundleDescriptor;

/**
 The Installed Type of the Application.
 */
typedef NS_ENUM(NSUInteger, FBApplicationInstallType) {
  FBApplicationInstallTypeUnknown = 0, /** The Application is unknown */
  FBApplicationInstallTypeSystem = 1, /** The Application is part of the Operating System */
  FBApplicationInstallTypeMac = 2, /** The Application is part of macOS */
  FBApplicationInstallTypeUser = 3, /** The Application has been installed by the user */
  FBApplicationInstallTypeUserEnterprise = 4, /** The Application has been installed by the user and signed with a distribution certificate */
  FBApplicationInstallTypeUserDevelopment = 5, /** The Application has been installed by the user and signed with a development certificate */
};

/**
 String Representations of the Installed Type.
 */
typedef NSString *FBApplicationInstallTypeString NS_STRING_ENUM;
extern FBApplicationInstallTypeString const FBApplicationInstallTypeStringUnknown;
extern FBApplicationInstallTypeString const FBApplicationInstallTypeStringSystem;
extern FBApplicationInstallTypeString const FBApplicationInstallTypeStringMac;
extern FBApplicationInstallTypeString const FBApplicationInstallTypeStringUser;
extern FBApplicationInstallTypeString const FBApplicationInstallTypeStringUserEnterprise;
extern FBApplicationInstallTypeString const FBApplicationInstallTypeStringUserDevelopment;

/**
 Keys from UserInfo about Applications
 */
typedef NSString *FBApplicationInstallInfoKey NS_EXTENSIBLE_STRING_ENUM;
extern FBApplicationInstallInfoKey const FBApplicationInstallInfoKeyApplicationType;
extern FBApplicationInstallInfoKey const FBApplicationInstallInfoKeyBundleIdentifier;
extern FBApplicationInstallInfoKey const FBApplicationInstallInfoKeyBundleName;
extern FBApplicationInstallInfoKey const FBApplicationInstallInfoKeyPath;
extern FBApplicationInstallInfoKey const FBApplicationInstallInfoKeySignerIdentity;

/**
 A container for an Application Bundle and how it is installed.
 */
@interface FBInstalledApplication : NSObject <NSCopying, FBJSONSerializable>

#pragma mark Initializers

/**
 The Designated Initializer.

 @param bundle the Application Bundle.
 @param installType the Install Type.
 @return a new Installed Application Instance.
 */
+ (instancetype)installedApplicationWithBundle:(FBBundleDescriptor *)bundle installType:(FBApplicationInstallType)installType;

/**
 The Designated Initializer.

 @param bundle the Application Bundle.
 @param installType the Install Type.
 @param dataContainer the Data Container Path.
 @return a new Installed Application Instance.
 */
+ (instancetype)installedApplicationWithBundle:(FBBundleDescriptor *)bundle installType:(FBApplicationInstallType)installType dataContainer:(nullable NSString *)dataContainer;

#pragma mark Properties

/**
 The Application Bundle.
 */
@property (nonatomic, copy, readonly) FBBundleDescriptor *bundle;

/**
 The Install Type of the Application.
 */
@property (nonatomic, assign, readonly) FBApplicationInstallType installType;

/**
 The data container path of the Application.
 */
@property (nonatomic, copy, nullable, readonly) NSString *dataContainer;

#pragma mark Install Type

/**
 Returns a String Represnting the Application Install Type.

 @param installType the install type enum.
 @return a string of the install type.
 */
+ (FBApplicationInstallTypeString)stringFromApplicationInstallType:(FBApplicationInstallType)installType;

/**
 Returns the FBApplicationInstallType from the string representation.

 @param installTypeString install type as a string
 @param signerIdentity the signer identity.
 @return an FBApplicationInstallType
 */
+ (FBApplicationInstallType)installTypeFromString:(nullable FBApplicationInstallTypeString)installTypeString signerIdentity:(nullable NSString *)signerIdentity;

@end

NS_ASSUME_NONNULL_END
