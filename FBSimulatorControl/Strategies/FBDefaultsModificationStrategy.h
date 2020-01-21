/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBLocalizationOverride;
@class FBSimulator;

/**
 A class for modifying defaults that reside on a Simulator.
 */
@interface FBDefaultsModificationStrategy : NSObject

/**
 A Strategy for modifying a plist.

 @param simulator the Simulator to use.
 @return a new strategy for the Simulator.
 */
+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator;

/**
 Modifies the defaults in a given domain or path.

 @param domainOrPath the domain or path to modify.
 @param defaults key value pair of defaults to set.
 @return a future that resolves when completed.
 */
- (FBFuture<NSNull *> *)modifyDefaultsInDomainOrPath:(nullable NSString *)domainOrPath defaults:(NSDictionary<NSString *, id> *)defaults;

@end

/**
 Modifies the Global Preferences for a Localization
 */
@interface FBLocalizationDefaultsModificationStrategy : FBDefaultsModificationStrategy

/**
 Adds a Localization Override.

 @param localizationOverride the Localization Override to use.
 @return a future that resolves when completed.
 */
- (FBFuture<NSNull *> *)overrideLocalization:(FBLocalizationOverride *)localizationOverride;

@end

/**
 Modifies the defaults for the locationd daemon.
 */
@interface FBLocationServicesModificationStrategy : FBDefaultsModificationStrategy

/**
 Approves Location Services for Applications.

 @param bundleIDs an NSArray<NSString> of bundle IDs to to authorize location settings for.
 @return a future that resolves when completed.
 */
- (FBFuture<NSNull *> *)approveLocationServicesForBundleIDs:(NSArray<NSString *> *)bundleIDs;

@end

/**
 Modifies the Frontboard Watchdog Override.
 */
@interface FBWatchdogOverrideModificationStrategy : FBDefaultsModificationStrategy

/**
 Overrides the default SpringBoard watchdog timer for the applications. You can use this to give your application more
 time to startup before being killed by SpringBoard. (SB's default is 20 seconds.)

 @param bundleIDs The bundle IDs of the applications to override.
 @param timeout The new startup timeout.
 @return YES if successful, NO otherwise.
 */
- (FBFuture<NSNull *> *)overrideWatchDogTimerForApplications:(NSArray<NSString *> *)bundleIDs timeout:(NSTimeInterval)timeout;

@end

/**
 Modifies the Keyboard Settings.
 */
@interface FBKeyboardSettingsModificationStrategy : FBDefaultsModificationStrategy

/**
 Prepares the Simulator Keyboard, prior to launch.
 1) Disables Caps Lock
 2) Disables Auto Capitalize
 3) Disables Auto Correction / QuickType

 @return the receiver, for chaining.
 */
- (FBFuture<NSNull *> *)setupKeyboard;

@end

NS_ASSUME_NONNULL_END
