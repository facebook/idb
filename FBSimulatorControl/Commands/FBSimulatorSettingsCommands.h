/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The Action Type for an Agent Launch.
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeApproval;

@class FBBundleDescriptor;
@class FBLocalizationOverride;
@class FBSimulator;

/**
 Modifies the Settings, Preferences & Defaults of a Simulator.
 */
@protocol FBSimulatorSettingsCommands <NSObject, FBiOSTargetCommand>

/**
 Enables or disables the hardware keyboard.

 @param enabled YES if enabled, NO if disabled.
 @return a Future that resolves when successful.
 */
- (FBFuture<NSNull *> *)setHardwareKeyboardEnabled:(BOOL)enabled;

/**
 Overrides the Global Localization of the Simulator.

 @param localizationOverride the Localization Override to set.
 @return A future that resolves when the setting change is complete.
 */
- (FBFuture<NSNull *> *)overridingLocalization:(FBLocalizationOverride *)localizationOverride;

/**
 Overrides the default SpringBoard watchdog timer for the applications. You can use this to give your application more
 time to startup before being killed by SpringBoard. (SB's default is 20 seconds.)

 @param bundleIDs The bundle IDs of the applications to override.
 @return A future that resolves when the setting change is complete.
 */
- (FBFuture<NSNull *> *)overrideWatchDogTimerForApplications:(NSArray<NSString *> *)bundleIDs withTimeout:(NSTimeInterval)timeout;

/**
 Grants access to the provided services.

 @param bundleIDs the bundle ids to provide access to.
 @return A future that resolves when the setting change is complete.
 */
- (FBFuture<NSNull *> *)grantAccess:(NSSet<NSString *> *)bundleIDs toServices:(NSSet<FBSettingsApprovalService> *)services;

/**
 Grants access to the provided deeplink scheme.

 @param bundleIDs the bundle ids to provide access to.
 @param scheme the deeplink scheme to allow
 @return A future that resolves when the setting change is complete.
 */
- (FBFuture<NSNull *> *)grantAccess:(NSSet<NSString *> *)bundleIDs toDeeplink:(NSString*)scheme;

/**
 Updates the contacts on the target, using the provided local databases.
 Takes local paths to AddressBook Databases. These replace the existing databases for the Address Book.
 Only sqlitedb paths should be provided, journaling files will be ignored.

 @param databaseDirectory the directory containing AddressBook.sqlitedb and AddressBookImages.sqlitedb paths.
 */
- (FBFuture<NSNull *> *)updateContacts:(NSString *)databaseDirectory;

/**
 Prepares the Simulator Keyboard, prior to launch.
 1) Disables Caps Lock
 2) Disables Auto Capitalize
 3) Disables Auto Correction / QuickType

 @return A future that resolves when the setting change is complete.
 */
- (FBFuture<NSNull *> *)setupKeyboard;

@end

/**
 Modifies the Settings, Preferences & Defaults of a Simulator.
 */
@interface FBSimulatorSettingsCommands : NSObject <FBSimulatorSettingsCommands>

@end

/**
 Bridges FBSettingsApproval to Simulators.
 */
@interface FBSettingsApproval (FBiOSTargetFuture) <FBiOSTargetFuture>

@end

NS_ASSUME_NONNULL_END
