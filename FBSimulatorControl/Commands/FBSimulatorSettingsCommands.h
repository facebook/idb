/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBBundleDescriptor;
@class FBSimulator;

/**
 Modifies the Settings, Preferences & Defaults of a Simulator.
 */
@protocol FBSimulatorSettingsCommandsProtocol <NSObject, FBiOSTargetCommand>

- (nonnull FBFuture<NSNull *> *)setHardwareKeyboardEnabled:(BOOL)enabled;
- (nonnull FBFuture<NSNull *> *)setPreference:(nonnull NSString *)name value:(nonnull NSString *)value type:(nullable NSString *)type domain:(nullable NSString *)domain;
- (nonnull FBFuture<NSString *> *)getCurrentPreference:(nonnull NSString *)name domain:(nullable NSString *)domain;
- (nonnull FBFuture<NSNull *> *)grantAccess:(nonnull NSSet<NSString *> *)bundleIDs toServices:(nonnull NSSet<FBTargetSettingsService> *)services;
- (nonnull FBFuture<NSNull *> *)revokeAccess:(nonnull NSSet<NSString *> *)bundleIDs toServices:(nonnull NSSet<FBTargetSettingsService> *)services;
- (nonnull FBFuture<NSNull *> *)grantAccess:(nonnull NSSet<NSString *> *)bundleIDs toDeeplink:(nonnull NSString *)scheme;
- (nonnull FBFuture<NSNull *> *)revokeAccess:(nonnull NSSet<NSString *> *)bundleIDs toDeeplink:(nonnull NSString *)scheme;
- (nonnull FBFuture<NSNull *> *)updateContacts:(nonnull NSString *)databaseDirectory;
- (nonnull FBFuture<NSNull *> *)clearContacts;
- (nonnull FBFuture<NSNull *> *)clearPhotos;

@end

// FBSimulatorSettingsCommands class is now implemented in Swift.
// The Swift header is imported by the umbrella header FBSimulatorControl.h.
