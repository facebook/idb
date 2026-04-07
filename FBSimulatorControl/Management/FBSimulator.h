/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorAccessibilityCommands.h>
#import <FBSimulatorControl/FBSimulatorApplicationCommands.h>
#import <FBSimulatorControl/FBSimulatorFileCommands.h>
#import <FBSimulatorControl/FBSimulatorKeychainCommands.h>
#import <FBSimulatorControl/FBSimulatorLaunchCtlCommands.h>
#import <FBSimulatorControl/FBSimulatorLifecycleCommands.h>
#import <FBSimulatorControl/FBSimulatorMediaCommands.h>
#import <FBSimulatorControl/FBSimulatorSettingsCommands.h>

@protocol FBControlCoreLogger;

@class FBAppleSimctlCommandExecutor;
@class FBControlCoreLogger;
@class FBSimulatorConfiguration;
@class FBSimulatorSet;
@class SimDevice;

/**
 An implementation of FBiOSTarget for iOS Simulators.
 */
@interface FBSimulator : NSObject <FBiOSTarget, FBAccessibilityCommands, FBMemoryCommands, FBFileCommands, FBLocationCommands, FBNotificationCommands, FBProcessSpawnCommands, FBSimulatorKeychainCommandsProtocol, FBSimulatorSettingsCommandsProtocol, FBSimulatorLifecycleCommandsProtocol, FBSimulatorLaunchCtlCommandsProtocol, FBSimulatorMediaCommandsProtocol, FBXCTestExtendedCommands, FBDapServerCommand, FBSimulatorApplicationCommandsProtocol, FBSimulatorFileCommandsProtocol>

#pragma mark Properties

/**
 The Underlying SimDevice.
 */
@property (nonnull, nonatomic, readonly, strong) SimDevice *device;

/**
 The Simulator Set that the Simulator belongs to.
 Reference to `FBSimulatorSet` results to a strong-strong reference cycle between `FBSimulatorSet` and `FBSimulator`.
 However, this cycle is explicitly broken by `FBSimulatorSet` when a `FBSimulator` is removed from the set that `FBSimulatorSet` wraps.
 */
@property (nonnull, nonatomic, readonly, strong) FBSimulatorSet *set;

/**
 The Product Family of the Simulator.
 */
@property (nonatomic, readonly, assign) FBControlCoreProductFamily productFamily;

/**
 A string representation of the Simulator State.
 */
@property (nonnull, nonatomic, readonly, copy) FBiOSTargetStateString stateString;

/**
 The Directory that Contains the Simulator's Data
 */
@property (nullable, nonatomic, readonly, copy) NSString *dataDirectory;

/**
 The FBSimulatorConfiguration representing this Simulator.
 Should be marked private when converting to Swift (was readwrite in private extension).
 */
@property (nonnull, nonatomic, readwrite, copy) FBSimulatorConfiguration *configuration;

/**
 A command executor for simctl
 */
@property (nonnull, nonatomic, readonly, strong) FBAppleSimctlCommandExecutor *simctlExecutor;

/**
 The directory path of the expected location of the CoreSimulator logs directory.
 */
@property (nonnull, nonatomic, readonly, copy) NSString *coreSimulatorLogsDirectory;

#pragma mark - Should be marked private when converting to Swift

@property (nonnull, nonatomic, readonly, strong) id forwarder;

+ (nonnull instancetype)fromSimDevice:(nonnull SimDevice *)device configuration:(nullable FBSimulatorConfiguration *)configuration set:(nonnull FBSimulatorSet *)set;
- (nonnull instancetype)initWithDevice:(nonnull SimDevice *)device configuration:(nonnull FBSimulatorConfiguration *)configuration set:(nullable FBSimulatorSet *)set auxillaryDirectory:(nonnull NSString *)auxillaryDirectory logger:(nonnull id<FBControlCoreLogger>)logger reporter:(nonnull id<FBEventReporter>)reporter;
- (nonnull instancetype)initWithDevice:(nonnull id)device logger:(nonnull id<FBControlCoreLogger>)logger reporter:(nonnull id<FBEventReporter>)reporter;

@end

#pragma mark - Accessibility Dispatcher

/**
 Category for accessibility translation dispatcher access.
 */
@interface FBSimulator (FBAccessibilityDispatcher)

/**
 Creates a translation dispatcher with the given translator.
 Used by tests to create a dispatcher with a mock translator.
 @param translator The AXPTranslator (or mock) to use for the dispatcher.
 @return A new dispatcher instance.
 */
+ (nonnull id)createAccessibilityTranslationDispatcherWithTranslator:(nonnull id)translator;

/**
 Returns the translation dispatcher for accessibility operations.
 In production, creates/returns the shared instance using the real translator.
 Test doubles can override this to return a mock dispatcher.
 @return The translation dispatcher.
 */
- (nonnull id)accessibilityTranslationDispatcher;

@end
