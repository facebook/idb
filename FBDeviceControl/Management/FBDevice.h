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

@class FBAMDevice;
@class FBAMRestorableDevice;
@class FBDeviceSet;
@class FBDeviceVideoRecordingCommands;
@class FBDeviceXCTestCommands;
@class FBiOSTargetCommandForwarder;
@protocol FBControlCoreLogger;

/**
 A class that represents an iOS Device.
 */
@interface FBDevice : NSObject <FBiOSTarget, FBDebuggerCommands, FBDeviceCommands, FBDiagnosticInformationCommands, FBLocationCommands, FBDeviceRecoveryCommandsProtocol, FBDeviceActivationCommandsProtocol, FBPowerCommands, FBDeveloperDiskImageCommands, FBSocketForwardingCommands, FBDeviceDebugSymbolsCommandsProtocol>

/**
 The Device Set to which the Device Belongs.
 */
@property (nullable, nonatomic, readonly, weak) FBDeviceSet *set;

/**
 Constructs an Operating System Version from a string.

 @param string the string to interpolate.
 @return an NSOperatingSystemVersion for the string.
 */
+ (NSOperatingSystemVersion)operatingSystemVersionFromString:(nonnull NSString *)string;

#pragma mark - Should be marked private when converting to Swift

@property (nullable, nonatomic, readwrite, strong) FBAMDevice *amDevice;
@property (nullable, nonatomic, readwrite, strong) FBAMRestorableDevice *restorableDevice;
@property (nonnull, nonatomic, readonly, strong) FBiOSTargetCommandForwarder *forwarder;

- (nonnull instancetype)initWithSet:(nonnull FBDeviceSet *)set amDevice:(nullable FBAMDevice *)amDevice restorableDevice:(nullable FBAMRestorableDevice *)restorableDevice logger:(nonnull id<FBControlCoreLogger>)logger;

@end
