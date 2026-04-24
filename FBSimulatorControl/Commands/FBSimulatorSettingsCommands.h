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
@class FBStatusBarOverride;

/**
 An enumeration of simulator settings that can be toggled on/off.
 Each value maps to a different underlying transport (SimDevice API, Darwin notification, etc.)
 but the public API is uniform: setSetting:enabled:.
 */
typedef NS_ENUM(NSUInteger, FBSimulatorSetting) {
  FBSimulatorSettingHardwareKeyboard,
  FBSimulatorSettingSlowAnimations,
  FBSimulatorSettingIncreaseContrast,
};

/**
 Dark/Light mode appearance.
 Values match UIUserInterfaceStyle used by SimDevice's setUIInterfaceStyle:error:.
 */
typedef NS_ENUM(NSInteger, FBSimulatorAppearance) {
  FBSimulatorAppearanceLight = 1, // UIUserInterfaceStyleLight
  FBSimulatorAppearanceDark = 2,  // UIUserInterfaceStyleDark
};

/**
 Dynamic Type content size categories.
 Values match the integer indices used by SimDevice's setContentSizeCategory:error:.
 */
typedef NS_ENUM(NSInteger, FBSimulatorContentSizeCategory) {
  FBSimulatorContentSizeCategoryExtraSmall = 1,
  FBSimulatorContentSizeCategorySmall = 2,
  FBSimulatorContentSizeCategoryMedium = 3,
  FBSimulatorContentSizeCategoryLarge = 4,
  FBSimulatorContentSizeCategoryExtraLarge = 5,
  FBSimulatorContentSizeCategoryExtraExtraLarge = 6,
  FBSimulatorContentSizeCategoryExtraExtraExtraLarge = 7,
  FBSimulatorContentSizeCategoryAccessibilityMedium = 8,
  FBSimulatorContentSizeCategoryAccessibilityLarge = 9,
  FBSimulatorContentSizeCategoryAccessibilityExtraLarge = 10,
  FBSimulatorContentSizeCategoryAccessibilityExtraExtraLarge = 11,
  FBSimulatorContentSizeCategoryAccessibilityExtraExtraExtraLarge = 12,
};
/**
 Modifies the Settings, Preferences & Defaults of a Simulator.
 */
@protocol FBSimulatorSettingsCommands <NSObject, FBiOSTargetCommand>

/**
 Enables or disables a simulator setting.

 @param setting the setting to modify.
 @param enabled YES to enable, NO to disable.
 @return a Future that resolves when successful.
 */
- (FBFuture<NSNull *> *)setSetting:(FBSimulatorSetting)setting enabled:(BOOL)enabled;

/**
 Returns the current appearance (dark/light mode).

 @return a Future that resolves with the current appearance.
 */
- (FBFuture<NSNumber *> *)currentAppearance;

/**
 Sets the simulator appearance (dark/light mode).

 @param appearance the appearance to set.
 @return a Future that resolves when successful.
 */
- (FBFuture<NSNull *> *)setAppearance:(FBSimulatorAppearance)appearance;

/**
 Returns the current Dynamic Type content size category.

 @return a Future that resolves with the current content size category.
 */
- (FBFuture<NSNumber *> *)currentContentSizeCategory;

/**
 Sets the Dynamic Type content size category.

 @param category the content size category to set.
 @return a Future that resolves when successful.
 */
- (FBFuture<NSNull *> *)setContentSizeCategory:(FBSimulatorContentSizeCategory)category;

/**
 Returns the current status bar overrides, or nil if no overrides are active.

 @return a Future that resolves with the current status bar overrides, or nil.
 */
- (FBFuture<FBStatusBarOverride *> *)currentStatusBarOverrides;

/**
 Overrides the status bar with the given configuration, or clears all overrides if nil.
 Only non-nil properties on the override object are applied.

 @param override the overrides to apply, or nil to clear all overrides.
 @return a Future that resolves when successful.
 */
- (FBFuture<NSNull *> *)overrideStatusBar:(nullable FBStatusBarOverride *)override;

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
 Sets the HealthKit authorisation status for one or more HKObjectType identifiers
 on a single bundle. This is the per-type counterpart of grantAccess:toServices:
 with FBTargetSettingsServiceHealth, which always operates on the curated default
 set and applies a single approve/revoke decision across both share and read.

 @param approved YES to mark the listed types as share+read authorised, NO to mark them as share+read denied.
 @param bundleID the target bundle id (must already have an entry in healthd's source database, see Discussion).
 @param typeIdentifiers HKQuantityTypeIdentifier* / HKCategoryTypeIdentifier* / etc. strings to set; pass an empty array to apply the curated default set.
 @return A future that resolves when the setting change is complete.

 @discussion The target bundle must have called requestAuthorization at least
 once on this simulator so healthd has a source row for it; otherwise the bridge
 returns a non-zero exit and the future fails. There is no API on the simulator
 to bootstrap that source row from outside the target bundle's process.
 */
- (FBFuture<NSNull *> *)setHealthAuthorization:(BOOL)approved
                                  forBundleID:(NSString *)bundleID
                              typeIdentifiers:(NSArray<NSString *> *)typeIdentifiers;

/**
 Resets every HealthKit authorisation record for a bundle id back to NotDetermined.

 @param bundleID the target bundle id.
 @return A future that resolves when the reset is complete.
 */
- (FBFuture<NSNull *> *)clearHealthAuthorizationForBundleID:(NSString *)bundleID;

/**
 Reads the HealthKit authorisation records for a bundle id and returns them as
 a JSON document.

 @param bundleID the target bundle id.
 @return A future that resolves with the JSON document printed by the bridge.
 */
- (FBFuture<NSString *> *)listHealthAuthorizationForBundleID:(NSString *)bundleID;

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

/**
 Clears all contacts from the simulator using the CNContacts framework.
 This spawns a helper binary inside the simulator that uses native Contacts APIs to delete all contacts.

 @return A future that resolves when all contacts have been deleted.
 */
- (FBFuture<NSNull *> *)clearContacts;

/**
 Clears all photos from the simulator using the Photos framework.
 This spawns a helper binary inside the simulator that uses native Photos APIs to delete all photos.

 @return A future that resolves when all photos have been deleted.
 */
- (FBFuture<NSNull *> *)clearPhotos;

/**
 Sets the network proxy for this simulator by writing directly to configd_sim's SCDynamicStore.
 All networking APIs (NSURLSession, NWConnection, CFNetwork) will honor these settings transparently.

 @param host The proxy host address (e.g. "127.0.0.1").
 @param port The proxy port number.
 @param type The proxy type: "http" (default) or "socks".
 @return A future that resolves when the proxy has been configured.
 */
- (FBFuture<NSNull *> *)setProxyWithHost:(NSString *)host port:(NSUInteger)port type:(NSString *)type;

/**
 Clears the network proxy for this simulator.

 @return A future that resolves when the proxy has been cleared.
 */
- (FBFuture<NSNull *> *)clearProxy;

/**
 Lists the current network proxy configuration from configd_sim's SCDynamicStore.

 @return A future that resolves with a JSON string of the current proxy configuration.
 */
- (FBFuture<NSString *> *)listProxy;

/**
 Sets the DNS servers for this simulator by writing to configd_sim's SCDynamicStore.

 @param servers Array of DNS server addresses (e.g. @[@"8.8.8.8", @"8.8.4.4"]).
 @return A future that resolves when the DNS servers have been configured.
 */
- (FBFuture<NSNull *> *)setDnsServers:(NSArray<NSString *> *)servers;

/**
 Clears the DNS configuration for this simulator.

 @return A future that resolves when the DNS configuration has been cleared.
 */
- (FBFuture<NSNull *> *)clearDns;

/**
 Lists the current DNS configuration from configd_sim's SCDynamicStore.

 @return A future that resolves with a JSON string of the current DNS configuration.
 */
- (FBFuture<NSString *> *)listDns;

@end

/**
 Modifies the Settings, Preferences & Defaults of a Simulator.
 */
@interface FBSimulatorSettingsCommands : NSObject <FBSimulatorSettingsCommands>

@end

NS_ASSUME_NONNULL_END
