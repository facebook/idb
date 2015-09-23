/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

/**
 A Value object that represents the Configuration of a Simulator.

 Class is designed around maximum convenience for specifying a configuration.
 For example to specify an iPad 2 on iOS 8.2:
 `FBSimulatorConfiguration.iPad2.iOS_8_2`.

 It is also possible to specify configurations based on a NSString.
 This is helpful when creating a device from something specified in an Environment Variable:
 `[FBSimulatorConfiguration.iPhone5 iOS:NSProcessInfo.processInfo.environment[@"TARGET_OS"]]`
 */
@interface FBSimulatorConfiguration : NSObject<NSCopying>

#pragma mark Properties

/**
 The Name of the Device to Simulate. Must not be nil.
 */
@property (nonatomic, copy, readonly) NSString *deviceName;

/**
 A String Representation of the OS Version of the Simulator. Must not be nil.
 */
@property (nonatomic, copy, readonly) NSString *osVersionString;

/**
 The Locale in which to Simulate, may be nil.
 */
@property (nonatomic, strong, readonly) NSLocale *locale;

/**
 A String representing the Scale at which to launch the Simulator.
 */
@property (nonatomic, copy, readonly) NSString *scaleString;

/**
 Returns the Default Configuration.
 The OS Version is derived from the SDK Version.
 */
+ (instancetype)defaultConfiguration;

#pragma mark Devices

/**
 An iPhone 4s.
 */
+ (instancetype)iPhone4s;
- (instancetype)iPhone4s;

/**
 An iPhone 5.
 */
+ (instancetype)iPhone5;
- (instancetype)iPhone5;

/**
 An iPhone 5s.
 */
+ (instancetype)iPhone5s;
- (instancetype)iPhone5s;

/**
 An iPhone 6.
 */
+ (instancetype)iPhone6;
- (instancetype)iPhone6;

/**
 An iPhone 6 Plus.
 */
+ (instancetype)iPhone6Plus;
- (instancetype)iPhone6Plus;

/**
 An iPad 2.
 */
+ (instancetype)iPad2;
- (instancetype)iPad2;

/**
 An iPad Retina.
 */
+ (instancetype)iPadRetina;
- (instancetype)iPadRetina;

/**
 An iPad Air.
 */
+ (instancetype)iPadAir;
- (instancetype)iPadAir;

/**
 An iPad Air.
 */
+ (instancetype)iPadAir2;
- (instancetype)iPadAir2;

/**
 A Device with the provided name.
 Will return nil, if no device with the given name could be found.
 */
+ (instancetype)named:(NSString *)deviceType;
- (instancetype)named:(NSString *)deviceType;

#pragma mark OS Versions

/**
 iOS 7.1
 */
- (instancetype)iOS_7_1;

/**
 iOS 8.0
 */
- (instancetype)iOS_8_0;

/**
 iOS 8.1
 */
- (instancetype)iOS_8_1;

/**
 iOS 8.2
 */
- (instancetype)iOS_8_2;

/**
 iOS 8.3
 */
- (instancetype)iOS_8_3;

/**
 iOS 8.4
 */
- (instancetype)iOS_8_4;

/**
 iOS 9.0
 */
- (instancetype)iOS_9_0;

/**
 iOS Device with the given OS version.
 Will return nil, if no OS with the given name could be found.
 */
+ (instancetype)iOS:(NSString *)version;

/**
 iOS Device with the given OS version.
 Will return nil, if no OS with the given name could be found.
 */
- (instancetype)iOS:(NSString *)version;

#pragma mark Device Scale

/**
 Launch at 25% Scale.
 */
- (instancetype)scale25Percent;

/**
 Launch at 50% Scale.
 */
- (instancetype)scale50Percent;

/**
 Launch at 75% Scale.
 */
- (instancetype)scale75Percent;

/**
 Launch at 100% Scale.
 */
- (instancetype)scale100Percent;

#pragma mark Locale

/**
 A new configuration with the provided locale
 */
- (instancetype)withLocale:(NSLocale *)locale;

/**
 A new configuration with the provided localeIdentifier.
 */
- (instancetype)withLocaleNamed:(NSString *)localeIdentifier;

@end
