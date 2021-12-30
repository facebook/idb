/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

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
@interface FBInstalledApplication : NSObject <NSCopying>

#pragma mark Initializers

/**
 The Designated Initializer.

 @param bundle the Application Bundle. This represents the bundle as-installed on the target, rather than pre-install.
 @param installType the Install Type.
 @param dataContainer the Data Container Path, may be nil.
 @return a new Installed Application Instance.
 */
+ (instancetype)installedApplicationWithBundle:(FBBundleDescriptor *)bundle installType:(FBApplicationInstallType)installType dataContainer:(nullable NSString *)dataContainer;

/**
 The Designated Initializer.

 @param bundle the Application Bundle. This represents the bundle as-installed on the target, rather than pre-install.
 @param installTypeString the string representation of the install type.
 @param dataContainer the Data Container Path, may be nil.
 @return a new Installed Application Instance.
 */
+ (instancetype)installedApplicationWithBundle:(FBBundleDescriptor *)bundle installTypeString:(nullable NSString *)installTypeString signerIdentity:(nullable NSString *)signerIdentity dataContainer:(nullable NSString *)dataContainer;

#pragma mark Properties

/**
 The Application Bundle as installed on the target. This may be missing information that is otherwise present from the installed bundle.
 */
@property (nonatomic, copy, readonly) FBBundleDescriptor *bundle;

/**
 The "Install Type" enum of the Application.
 */
@property (nonatomic, assign, readonly) FBApplicationInstallType installType;

/**
 The "Install Type" enum of the Application, represented as a string.
 */
@property (nonatomic, copy, readonly) NSString *installTypeString;

/**
 The data container path of the Application.
 */
@property (nonatomic, copy, nullable, readonly) NSString *dataContainer;

@end

NS_ASSUME_NONNULL_END
