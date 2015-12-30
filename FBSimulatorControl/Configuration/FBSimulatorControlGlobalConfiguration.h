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
 An Environment Variable: 'FBSIMULATORCONTROL_LOGGING' to enable logging of Informational Messages to stderr.
 */
extern NSString *const FBSimulatorControlStderrLogging;

/**
 An Environment Variable: 'FBSIMULATORCONTROL_DEBUG_LOGGING' to enable logging of Debug Messages to stderr.
 */
extern NSString *const FBSimulatorControlDebugLogging;

/**
 Environment Globals & other derived constants.
 */
@interface FBSimulatorControlGlobalConfiguration : NSObject

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
 A Timeout Value when waiting on events that should happen 'fast'
 */
+ (NSTimeInterval)fastTimeout;

/**
 A Timeout Value when waiting on events that will take some time longer than 'fast' events.
 */
+ (NSTimeInterval)regularTimeout;

/**
 A Timeout Value when waiting on events that will a longer period of time.
 */
+ (NSTimeInterval)slowTimeout;

/**
 YES if passing a custom SimDeviceSet to the Simulator App is Supported.
 */
+ (BOOL)supportsCustomDeviceSets;

/**
 YES if informattional logging should be written to stderr, NO otherwise.
 */
+ (BOOL)stderrLoggingEnabled;

/**
 YES if Debug information should be written to stderr, NO otherwise.
 */
+ (BOOL)debugLoggingEnabled;

/**
 The default logger to send log messages to.
 */
+ (id<FBSimulatorLogger>)defaultLogger;

/**
 A Description of the Current Configuration.
 */
+ (NSString *)description;

@end

/**
 Update the Global Configuration at (early) runtime by modifying the Environment.
 These Methods should typically be called *before any other* method in FBSimulatorControl.
 */
@interface FBSimulatorControlGlobalConfiguration (Environment)

/**
 Update the current process environment to enable logging to stderr.

 @param enabled YES if stderr logging should be enabled, NO otherwise.
 */
+ (void)setStderrLoggingEnabled:(BOOL)enabled;

/**
 Update the current process environment to enable debug logging to stderr.

 @param enabled YES if stderr debuglogging should be enabled, NO otherwise.
 */
+ (void)setDebugLoggingEnabled:(BOOL)enabled;

@end
