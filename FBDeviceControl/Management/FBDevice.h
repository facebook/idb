/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBDeviceActivationCommands.h>
#import <FBDeviceControl/FBDeviceCommands.h>
#import <FBDeviceControl/FBDeviceDebugSymbolsCommands.h>
#import <FBDeviceControl/FBDeviceRecoveryCommands.h>
#import <FBDeviceControl/FBDeviceSocketForwardingCommands.h>

NS_ASSUME_NONNULL_BEGIN

@class FBDeviceSet;
@protocol FBControlCoreLogger;

/**
 A class that represents an iOS Device.
 */
@interface FBDevice : NSObject <FBiOSTarget, FBDebuggerCommands, FBDeviceCommands, FBDiagnosticInformationCommands, FBLocationCommands, FBDeviceRecoveryCommands, FBDeviceActivationCommands, FBPowerCommands, FBDeveloperDiskImageCommands, FBSocketForwardingCommands, FBDeviceDebugSymbolsCommands>

/**
 The Device Set to which the Device Belongs.
 */
@property (nonatomic, weak, readonly) FBDeviceSet *set;

/**
 Constructs an Operating System Version from a string.

 @param string the string to interpolate.
 @return an NSOperatingSystemVersion for the string.
 */
+ (NSOperatingSystemVersion)operatingSystemVersionFromString:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
