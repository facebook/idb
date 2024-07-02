/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBBundleDescriptor;
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
 Sets preference by name and value for a given domain. If domain not specified assumed to be Apple Global Domain

 @param name preference name
 @param value preference value
 @param type preverence value type. If null defaults to `string`.
 @param domain preference domain - optional
 @return a Future that resolves when successful.
 */
- (FBFuture<NSNull *> *)setPreference:(NSString *)name value:(NSString *)value type:(nullable NSString *)type domain:(nullable NSString *)domain;

/**
 Gets a preference value by its name and domain. If domain not specified assumed to be Apple Global Domain

 @param name preference name
 @param domain domain to search - optional
 @return a Future that resolves with the current preference value
 */
- (FBFuture<NSString *> *)getCurrentPreference:(NSString *)name domain:(nullable NSString *)domain;

/**
 Grants access to the provided services.

 @param bundleIDs the bundle ids to provide access to.
 @return A future that resolves when the setting change is complete.
 */
- (FBFuture<NSNull *> *)grantAccess:(NSSet<NSString *> *)bundleIDs toServices:(NSSet<FBTargetSettingsService> *)services;

/**
 Revokes access to the provided services.

 @param bundleIDs the bundle ids to revoke access to.
 @return A future that resolves when the setting change is complete.
 */
- (FBFuture<NSNull *> *)revokeAccess:(NSSet<NSString *> *)bundleIDs toServices:(NSSet<FBTargetSettingsService> *)services;

/**
 Grants access to the provided deeplink scheme.

 @param bundleIDs the bundle ids to provide access to.
 @param scheme the deeplink scheme to allow
 @return A future that resolves when the setting change is complete.
 */
- (FBFuture<NSNull *> *)grantAccess:(NSSet<NSString *> *)bundleIDs toDeeplink:(NSString*)scheme;

/**
 Revokes access to the provided deeplink scheme.

 @param bundleIDs the bundle ids to revoke access to.
 @param scheme the deeplink scheme
 @return A future that resolves when the setting change is complete.
 */
- (FBFuture<NSNull *> *)revokeAccess:(NSSet<NSString *> *)bundleIDs toDeeplink:(NSString*)scheme;

/**
 Updates the contacts on the target, using the provided local databases.
 Takes local paths to AddressBook Databases. These replace the existing databases for the Address Book.
 Only sqlitedb paths should be provided, journaling files will be ignored.

 @param databaseDirectory the directory containing AddressBook.sqlitedb and AddressBookImages.sqlitedb paths.
 */
- (FBFuture<NSNull *> *)updateContacts:(NSString *)databaseDirectory;

@end

/**
 Modifies the Settings, Preferences & Defaults of a Simulator.
 */
@interface FBSimulatorSettingsCommands : NSObject <FBSimulatorSettingsCommands>

@end

NS_ASSUME_NONNULL_END
