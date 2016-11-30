/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBLocalizationOverride;
@class FBSimulator;

/**
 Modifies a Plist on the Simulator.
 */
@interface FBPlistModificationStrategy : NSObject

/**
 A Strategy for modifying a plist.

 @param simulator the Simulator to use.
 @return a new strategy for the Simulator.
 */
+ (instancetype)strategyWithSimulator:(FBSimulator *)simulator;

/**
 Amends a Plist, relative to a root path.

 @param relativePath the relative path from the Simulator root.
 @param error an error out for any error that occurs.
 @param block the block to use for modifications.
 @return YES if successful, NO otherwise.
 */
- (BOOL)amendRelativeToPath:(NSString *)relativePath error:(NSError **)error amendWithBlock:( void(^)(NSMutableDictionary<NSString *, id> *) )block;

@end

/**
 Modifies the Global Preferences for a Localization
 */
@interface FBLocalizationDefaultsModificationStrategy : FBPlistModificationStrategy

/**
 Adds a Localization Override.

 @param localizationOverride the Localization Override to use.
 @param error an error out for any error that occurs.
 @return YES if succesful, NO otherwise.
 */
- (BOOL)overideLocalization:(FBLocalizationOverride *)localizationOverride error:(NSError **)error;

@end

/**
 Modifies the locationd plist.
 */
@interface FBLocationServicesModificationStrategy : FBPlistModificationStrategy

/**
 Adds a Localization Override.

 @param bundleIDs an NSArray<NSString> of bundle IDs to to authorize location settings for.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)overideLocalizations:(NSArray<NSString *> *)bundleIDs error:(NSError **)error;

@end

/**
 Modifies the Frontboard Watchdog Override.
 */
@interface FBWatchdogOverrideModificationStrategy : FBPlistModificationStrategy

/**
 Overrides the default SpringBoard watchdog timer for the applications. You can use this to give your application more
 time to startup before being killed by SpringBoard. (SB's default is 20 seconds.)

 @param bundleIDs The bundle IDs of the applications to override.
 @param timeout The new startup timeout.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
- (BOOL)overrideWatchDogTimerForApplications:(NSArray<NSString *> *)bundleIDs timeout:(NSTimeInterval)timeout error:(NSError **)error;

@end

/**
 Modifies the Keyboard Settings.
 */
@interface FBKeyboardSettingsModificationStrategy : FBPlistModificationStrategy

/**
 Prepares the Simulator Keyboard, prior to launch.
 1) Disables Caps Lock
 2) Disables Auto Capitalize
 3) Disables Auto Correction / QuickType

 @param error an error out for any error that occurs.
 @return the reciever, for chaining.
 */
- (BOOL)setupKeyboardWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
