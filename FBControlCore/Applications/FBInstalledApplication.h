/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBJSONConversion.h>

NS_ASSUME_NONNULL_BEGIN

@class FBApplicationBundle;

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
extern FBApplicationInstallInfoKey const FBApplicationInstallInfoKeyBundleName;
extern FBApplicationInstallInfoKey const FBApplicationInstallInfoKeyBundleIdentifier;


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
+ (instancetype)installedApplicationWithBundle:(FBApplicationBundle *)bundle installType:(FBApplicationInstallType)installType;

/**
 The Designated Initializer.

 @param bundle the Application Bundle.
 @param installType the Install Type.
 @param dataContainer the Data Container Path.
 @return a new Installed Application Instance.
 */
+ (instancetype)installedApplicationWithBundle:(FBApplicationBundle *)bundle installType:(FBApplicationInstallType)installType dataContainer:(nullable NSString *)dataContainer;

#pragma mark Properties

/**
 The Application Bundle.
 */
@property (nonatomic, copy, readonly) FBApplicationBundle *bundle;

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
 */
+ (FBApplicationInstallTypeString)stringFromApplicationInstallType:(FBApplicationInstallType)installType;

/**
 Returns the FBApplicationInstallType from the string representation.

 @param installTypeString install type as a string
 */
+ (FBApplicationInstallType)installTypeFromString:(nullable FBApplicationInstallTypeString)installTypeString;

@end

NS_ASSUME_NONNULL_END
