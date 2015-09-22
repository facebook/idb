/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBInteraction.h>
#import <FBSimulatorControl/FBSimulator.h>

@class FBSimulator;
@class FBSimulatorApplication;
@class FBSimulatorConfiguration;

/**
 Pre-session interactions used pre-launch of a Simulator
 */
@interface FBSimulatorInteraction : FBInteraction

/**
 Returns a new Interaction for the provided Simulator.

 @param simulator the Simulator to interact with, must not be nil.
 */
+ (instancetype)withSimulator:(FBSimulator *)simulator;

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

/**
 Some conveniences for making the interactions associated with a Simulator Configuration.
 */
@interface FBSimulatorInteraction (Convenience)

/**
 Makes an interaction by:
 1) Setting the Locale (if the configuration contains one)
 2) Sets up the keyboard

 @param configuration the configuration to apply.
 */
- (instancetype)configureWith:(FBSimulatorConfiguration *)configuration;

@end

/**
 Helps make a more fluent API for interacting with Simulators.
 */
@interface FBSimulator (FBSimulatorInteraction)

/**
 Creates an `FBSimulatorInteraction` for the reciever.
 */
- (FBSimulatorInteraction *)interact;

@end
