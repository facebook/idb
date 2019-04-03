/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBJSONConversion.h>

NS_ASSUME_NONNULL_BEGIN

/**
 XCode constants.
 These values can be accessed before the Private Frameworks are loaded.
 */
@interface FBXcodeConfiguration : NSObject <FBJSONSerializable>

/**
 The File Path of Apple's 'Apple Configurator' Application, if installed.
 */
@property (nonatomic, copy, readonly, nullable, class) NSString *appleConfiguratorApplicationPath;

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
 YES if Xcode 7 or greater, NO Otherwise.
 */
@property (nonatomic, assign, readonly, class) BOOL isXcode7OrGreater;

/**
 YES if Xcode 8 or greater, NO Otherwise.
 */
@property (nonatomic, assign, readonly, class) BOOL isXcode8OrGreater;

/**
 YES if Xcode 9 or greater, NO Otherwise.
 */
@property (nonatomic, assign, readonly, class) BOOL isXcode9OrGreater;

/**
 YES if Xcode 10 or greater, NO Otherwise.
 */
@property (nonatomic, assign, readonly, class) BOOL isXcode10OrGreater;

/**
 YES if passing a custom SimDeviceSet to the Simulator App is Supported.
 */
@property (nonatomic, assign, readonly, class) BOOL supportsCustomDeviceSets;

/**
 A Description of the Current Configuration.
 */
@property (nonatomic, copy, readonly, class) NSString *description;

@end


NS_ASSUME_NONNULL_END
