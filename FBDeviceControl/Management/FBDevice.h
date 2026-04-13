/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBDeviceCommands.h>
#import <FBDeviceControl/FBDeviceDebugSymbolsCommands.h>

@class FBAMDevice;
@class FBAMRestorableDevice;
@class FBDeviceSet;
@class FBDeviceVideoRecordingCommands;
@class FBDeviceXCTestCommands;
@class FBiOSTargetCommandForwarder;
@protocol FBControlCoreLogger;

#if __has_include(<FBDeviceControl/FBDeviceControl-Swift.h>)
 #import <FBDeviceControl/FBDeviceControl-Swift.h>
#endif

/**
 A class that represents an iOS Device.
 */
@interface FBDevice : NSObject <FBiOSTarget, FBDebuggerCommands, FBDeviceCommands, FBDiagnosticInformationCommands, FBLocationCommands, FBPowerCommands, FBDeveloperDiskImageCommands>

#pragma mark - FBiOSTarget / FBiOSTargetInfo Protocol Members
// These are implemented via @synthesize or method implementations in FBDevice.m.
// They must be declared explicitly for Swift visibility since the protocols are Swift-defined.

@property (nonnull, nonatomic, readonly, copy) NSString *uniqueIdentifier;
@property (nonnull, nonatomic, readonly, copy) NSString *udid;
@property (nonnull, nonatomic, readonly, copy) NSString *name;
@property (nonnull, nonatomic, readonly, strong) FBDeviceType *deviceType;
@property (nonnull, nonatomic, readonly, copy) NSArray<FBArchitecture> *architectures;
@property (nonnull, nonatomic, readonly, strong) FBOSVersion *osVersion;
@property (nonnull, nonatomic, readonly, copy) NSDictionary<NSString *, id> *extendedInformation;
@property (nonatomic, readonly, assign) FBiOSTargetType targetType;
@property (nonatomic, readonly, assign) FBiOSTargetState state;
@property (nullable, nonatomic, readonly, strong) id<FBControlCoreLogger> logger;
@property (nullable, nonatomic, readonly, copy) NSString *customDeviceSetPath;
@property (nonnull, nonatomic, readonly, strong) FBTemporaryDirectory *temporaryDirectory;
@property (nonnull, nonatomic, readonly, copy) NSString *auxillaryDirectory;
@property (nonnull, nonatomic, readonly, copy) NSString *runtimeRootDirectory;
@property (nonnull, nonatomic, readonly, copy) NSString *platformRootDirectory;
@property (nullable, nonatomic, readonly, strong) FBiOSTargetScreenInfo *screenInfo;
@property (nonnull, nonatomic, readonly, strong) dispatch_queue_t workQueue;
@property (nonnull, nonatomic, readonly, strong) dispatch_queue_t asyncQueue;

// Forwarded command methods declared for ObjC/Swift visibility
- (nonnull FBFuture<NSNull *> *)activate;
- (nonnull FBFuture<NSNull *> *)enterRecovery;
- (nonnull FBFuture<NSNull *> *)exitRecovery;
- (nonnull FBFuture *)ensureDeveloperDiskImageIsMounted;
- (nonnull FBFuture<FBInstalledApplication *> *)installedApplicationWithBundleID:(nonnull NSString *)bundleID;

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
