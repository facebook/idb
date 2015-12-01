/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBSimulatorControl/FBSimulatorInteraction.h>

@interface FBSimulatorInteraction (Setup)

/**
 Sets the locale for the simulator.

 @param locale the locale to set, must not be nil.
 */
- (instancetype)setLocale:(NSLocale *)locale;

/**
 Authorizes the Location Settings for the provided application.

 @param application the Application to authorize settings for.
 */
- (instancetype)authorizeLocationSettingsForApplication:(FBSimulatorApplication *)application;

/**
 Setups keyboard for simulator
 1) Disables Caps Lock
 2) Disables Auto Capitalize
 3) Disables Auto Correction / QuickType
 */
- (instancetype)setupKeyboard;

@end
