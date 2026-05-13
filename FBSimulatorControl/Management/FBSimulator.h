/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorAccessibilityCommands.h>

@protocol FBControlCoreLogger;

@class FBAppleSimctlCommandExecutor;
@class FBControlCoreLogger;
@class FBSimulatorBootConfiguration;
@class FBSimulatorConfiguration;
@class FBSimulatorSet;
@class FBTargetCommandCache;
@class SimDevice;

/**
 An implementation of FBiOSTarget for iOS Simulators.
 */
// Protocol conformances declared in Swift via extensions:
// FBSimulatorKeychainCommandsProtocol, FBSimulatorSettingsCommandsProtocol,
// FBSimulatorLifecycleCommandsProtocol, FBSimulatorLaunchCtlCommandsProtocol,
// FBSimulatorMediaCommandsProtocol, FBSimulatorApplicationCommandsProtocol,
// FBSimulatorFileCommandsProtocol
@interface FBSimulator : NSObject <FBiOSTarget, FBAccessibilityCommands, FBProcessSpawnCommands>

#pragma mark FBiOSTargetInfo / FBiOSTarget Protocol Members

/**
 FBiOSTargetInfo protocol members - implemented in FBSimulator.m.
 Must be declared explicitly for Swift visibility since the protocols are Swift-defined.
 */
@property (nonnull, nonatomic, readonly, copy) NSString *uniqueIdentifier;
@property (nonnull, nonatomic, readonly, copy) NSString *udid;
@property (nonnull, nonatomic, readonly, copy) NSString *name;
@property (nonnull, nonatomic, readonly, strong) FBDeviceType *deviceType;
@property (nonnull, nonatomic, readonly, copy) NSArray<FBArchitecture> *architectures;
@property (nonnull, nonatomic, readonly, strong) FBOSVersion *osVersion;
@property (nonnull, nonatomic, readonly, copy) NSDictionary<NSString *, id> *extendedInformation;
@property (nonatomic, readonly, assign) FBiOSTargetType targetType;
@property (nonatomic, readonly, assign) FBiOSTargetState state;

/**
 FBiOSTarget protocol members - implemented in FBSimulator.m.
 */
@property (nullable, nonatomic, readonly, strong) id<FBControlCoreLogger> logger;
@property (nullable, nonatomic, readonly, copy) NSString *customDeviceSetPath;
@property (nonnull, nonatomic, readonly, strong) FBTemporaryDirectory *temporaryDirectory;
@property (nonnull, nonatomic, readonly, copy) NSString *auxillaryDirectory;
@property (nonnull, nonatomic, readonly, copy) NSString *runtimeRootDirectory;
@property (nonnull, nonatomic, readonly, copy) NSString *platformRootDirectory;
@property (nullable, nonatomic, readonly, strong) FBiOSTargetScreenInfo *screenInfo;
@property (nonnull, nonatomic, readonly, strong) dispatch_queue_t workQueue;
@property (nonnull, nonatomic, readonly, strong) dispatch_queue_t asyncQueue;
- (NSComparisonResult)compare:(nonnull id<FBiOSTarget>)target;
- (BOOL)requiresBundlesToBeSigned;
- (nonnull NSDictionary<NSString *, NSString *> *)replacementMapping;
- (nonnull NSDictionary<NSString *, NSString *> *)environmentAdditions;

// FBProcessSpawnCommands (forwarded at runtime)
- (nonnull FBFuture *)launchProcess:(nonnull FBProcessSpawnConfiguration *)configuration;

// FBSimulatorLifecycleCommandsProtocol (forwarded at runtime)
- (nonnull FBFuture<NSNull *> *)disconnectWithTimeout:(NSTimeInterval)timeout logger:(nullable id<FBControlCoreLogger>)logger;
- (nonnull FBFuture *)connectToBridge;
- (nonnull FBFuture *)connectToFramebuffer;

// FBSimulatorLaunchCtlCommandsProtocol (forwarded at runtime)
- (nonnull FBFuture<NSDictionary *> *)serviceNamesAndProcessIdentifiersMatching:(nonnull NSRegularExpression *)regex;
- (nonnull FBFuture<NSArray *> *)firstServiceNameAndProcessIdentifierMatching:(nonnull NSRegularExpression *)regex;
- (nonnull FBFuture<NSString *> *)stopServiceWithName:(nonnull NSString *)serviceName;
- (nonnull FBFuture<NSString *> *)serviceNameForProcessIdentifier:(pid_t)processIdentifier;
- (nonnull FBFuture<NSString *> *)startServiceWithName:(nonnull NSString *)serviceName;

// FBPowerCommands / FBEraseCommands / FBSimulatorLifecycleCommandsProtocol (forwarded)
- (nonnull FBFuture<NSNull *> *)shutdown;
- (nonnull FBFuture<NSNull *> *)reboot;
- (nonnull FBFuture<NSNull *> *)erase;
- (nonnull FBFuture<NSNull *> *)boot:(nonnull FBSimulatorBootConfiguration *)configuration;

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
@property (nonnull, nonatomic, readonly, strong) FBTargetCommandCache *commandCache;

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
