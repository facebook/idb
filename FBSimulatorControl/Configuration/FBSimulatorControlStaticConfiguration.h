/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@protocol FBSimulatorLogger;

/**
 An Environment Variable that is inserted into launched Simulator.app processes
 in order to easily identify the Simulator UUID that they were launched to run against.
 */
extern NSString *const FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID;

/**
 An Environment Variable to enable Simulator Debug Logging.
 */
extern NSString *const FBSimulatorControlDebugLogging;

/**
 An Environment Variable to enable automatic evaluation of Global Preconditions.
 */
extern NSString *const FBSimulatorControlAutomaticallyLoadFrameworks;

/**
 Environment Globals & other derived constants
 */
@interface FBSimulatorControlStaticConfiguration : NSObject

/**
 If set to YES, Global Predocitions will automatically be evaluated on launch.
 */
+ (BOOL)automaticallyLoadFrameworks;

/**
 The path to of Xcode's /Xcode.app/Contents/Developer directory.
 */
+ (NSString *)developerDirectory;

/**
 The SDK Version of the current Xcode Version as a Decimal Number.
 */
+ (NSDecimalNumber *)sdkVersionNumber;

/**
 Formatter for the SDK Version a string
 */
+ (NSNumberFormatter *)sdkVersionNumberFormatter;

/**
 The SDK Version of the current Xcode Version as a String.
 */
+ (NSString *)sdkVersion;

/**
 YES if passing a custom SimDeviceSet to the Simulator App is Supported.
 */
+ (BOOL)supportsCustomDeviceSets;

/**
 Global override for Simulator Debug Logging
 */
+ (BOOL)simulatorDebugLoggingEnabled;

/**
 The Default logger to send log messages to.
 */
+ (id<FBSimulatorLogger>)defaultLogger;

/**
 A Description of the Current Configuration.
 */
+ (NSString *)description;

@end
