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

@class FBApplicationDescriptor;
@class FBLocalizationOverride;
@class FBSimulator;
@class FBSimulatorBootConfiguration;

/**
 Modifies the Settings, Preferences & Defaults of a Simulator.
 */
@protocol FBSimulatorSettingsCommands <NSObject>

/**
 Overrides the Global Localization of the Simulator.

 @param localizationOverride the Localization Override to set.
 @param error an error out for any error that occurs.
 @return YES if the command succeeds, NO otherwise,
 */
- (BOOL)overridingLocalization:(FBLocalizationOverride *)localizationOverride error:(NSError **)error;

/**
 Authorizes the Location Settings for the provided bundleIDs

 @param bundleIDs an NSArray<NSString> of bundle IDs to to authorize location settings for.
 @param error an error out for any error that occurs.
 @return YES if the command succeeds, NO otherwise,
 */
- (BOOL)authorizeLocationSettings:(NSArray<NSString *> *)bundleIDs error:(NSError **)error;

/**
 Authorizes the Location Settings for the provided application.

 @param application the Application to authorize settings for.
 @param error an error out for any error that occurs.
 @return YES if the command succeeds, NO otherwise,
 */
- (BOOL)authorizeLocationSettingForApplication:(FBApplicationDescriptor *)application error:(NSError **)error;

/**
 Overrides the default SpringBoard watchdog timer for the applications. You can use this to give your application more
 time to startup before being killed by SpringBoard. (SB's default is 20 seconds.)

 @param bundleIDs The bundle IDs of the applications to override.
 @param timeout The new startup timeout.
 @param error an error out for any error that occurs.
 @return YES if the command succeeds, NO otherwise,
 */
- (BOOL)overrideWatchDogTimerForApplications:(NSArray<NSString *> *)bundleIDs withTimeout:(NSTimeInterval)timeout error:(NSError **)error;

/**
 Prepares the Simulator Keyboard, prior to launch.
 1) Disables Caps Lock
 2) Disables Auto Capitalize
 3) Disables Auto Correction / QuickType

 @param error an error out for any error that occurs.
 @return YES if the command succeeds, NO otherwise,
 */
- (BOOL)setupKeyboardWithError:(NSError **)error;

@end

/**
 Modifies the Settings, Preferences & Defaults of a Simulator.
 */
@interface FBSimulatorSettingsCommands : NSObject <FBSimulatorSettingsCommands>

/**
 Creates and returns a new Commmands Instance.

 @param simulator the Simulator to operate on.
 @return a strategy for the provided Simulator.
 */
+ (instancetype)commandWithSimulator:(FBSimulator *)simulator;

@end

NS_ASSUME_NONNULL_END
