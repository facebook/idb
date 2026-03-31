/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class FBBundleDescriptor;

/**
 XCode constants.
 These values can be accessed before the Private Frameworks are loaded.
 */
@interface FBXcodeConfiguration : NSObject

/**
 The File Path to of Xcode's /Xcode.app/Contents/Developer directory.
 */
@property (class, nonnull, nonatomic, readonly, copy) NSString *developerDirectory;

/**
 The File Path to of Xcode's /Xcode.app/Contents directory.
 */
@property (class, nonnull, nonatomic, readonly, copy) NSString *contentsDirectory;

/**
 The Version Number for the Xcode defined by the Developer Directory.
 */
@property (class, nonnull, nonatomic, readonly, copy) NSDecimalNumber *xcodeVersionNumber;

/**
 The Version Number for the Xcode defined by the Developer Directory.
 */
@property (class, nonatomic, readonly, assign) NSOperatingSystemVersion xcodeVersion;

/**
 The SDK Version for the Xcode defined by the Developer Directory.
 */
@property (class, nonnull, nonatomic, readonly, copy) NSDecimalNumber *iosSDKVersionNumber;

/**
 Formatter for the SDK Version a string
 */
@property (class, nonnull, nonatomic, readonly, strong) NSDecimalNumber *iosSDKVersionNumberFormatter;

/**
 The SDK Version of the current Xcode Version as a String.
 */
@property (class, nonnull, nonatomic, readonly, copy) NSString *iosSDKVersion;

/**
 YES if Xcode 12 or greater, NO Otherwise.
 */
@property (class, nonatomic, readonly, assign) BOOL isXcode12OrGreater;

/**
 YES if Xcode 12.5 or greater, NO Otherwise.
 */
@property (class, nonatomic, readonly, assign) BOOL isXcode12_5OrGreater;

/**
 A Description of the Current Configuration.
 */
@property (class, nonnull, nonatomic, readonly, copy) NSString *description;

/**
 A bundle descriptor representing SimulatorApp.
 */
@property (class, nonnull, nonatomic, readonly, copy) FBBundleDescriptor *simulatorApp;

/**
 Return Developer directory if exist or nil.
 */
+ (nullable NSString *)getDeveloperDirectoryIfExists;

@end
