/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

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
extern FBApplicationInstallInfoKey _Nonnull const FBApplicationInstallInfoKeyApplicationType;
extern FBApplicationInstallInfoKey _Nonnull const FBApplicationInstallInfoKeyBundleIdentifier;
extern FBApplicationInstallInfoKey _Nonnull const FBApplicationInstallInfoKeyBundleName;
extern FBApplicationInstallInfoKey _Nonnull const FBApplicationInstallInfoKeyPath;
extern FBApplicationInstallInfoKey _Nonnull const FBApplicationInstallInfoKeySignerIdentity;

// FBInstalledApplication class is now implemented in Swift.
// Import FBControlCore/FBControlCore.h or FBControlCore-Swift.h to access it.
