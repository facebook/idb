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
 XCode constants.
 These values can be accessed before the Private Frameworks are loaded.
 */
@interface FBXcodeConfiguration : NSObject

/**
 The File Path to of Xcode's /Xcode.app/Contents/Developer directory.
 */
@property (nonatomic, copy, readonly, class) NSString *developerDirectory;

/**
 The File Path to of Xcode's /Xcode.app/Contents directory.
 */
@property (nonatomic, copy, readonly, class) NSString *contentsDirectory;

/**
 The Version Number for the Xcode defined by the Developer Directory.
 */
@property (nonatomic, copy, readonly, class) NSDecimalNumber *xcodeVersionNumber;

/**
 The Version Number for the Xcode defined by the Developer Directory.
 */
@property (nonatomic, assign, readonly, class) NSOperatingSystemVersion xcodeVersion;

/**
 The SDK Version for the Xcode defined by the Developer Directory.
 */
@property (nonatomic, copy, readonly, class) NSDecimalNumber *iosSDKVersionNumber;

/**
 Formatter for the SDK Version a string
 */
@property (nonatomic, strong, readonly, class) NSDecimalNumber *iosSDKVersionNumberFormatter;

/**
 The SDK Version of the current Xcode Version as a String.
 */
@property (nonatomic, copy, readonly, class) NSString *iosSDKVersion;

/**
 YES if Xcode 9 or greater, NO Otherwise.
 */
@property (nonatomic, assign, readonly, class) BOOL isXcode9OrGreater;

/**
 YES if Xcode 10 or greater, NO Otherwise.
 */
@property (nonatomic, assign, readonly, class) BOOL isXcode10OrGreater;

/**
 YES if Xcode 12 or greater, NO Otherwise.
 */
@property (nonatomic, assign, readonly, class) BOOL isXcode12OrGreater;

/**
 YES if Xcode 12.5 or greater, NO Otherwise.
 */
@property (nonatomic, assign, readonly, class) BOOL isXcode12_5OrGreater;

/**
 A Description of the Current Configuration.
 */
@property (nonatomic, copy, readonly, class) NSString *description;

/**
 A bundle descriptor representing SimulatorApp.
 */
@property (nonatomic, copy, readonly, class) FBBundleDescriptor *simulatorApp;


/**
 Return Developer directory if exist or nil.
 */
+ (nullable NSString *)getDeveloperDirectoryIfExists;

@end


NS_ASSUME_NONNULL_END
