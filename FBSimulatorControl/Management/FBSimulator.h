/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <CompanionUtilities/CompanionUtilities-Swift.h>
#import <FBControlCore/FBControlCore.h>

@protocol FBControlCoreLogger;

@class FBAppleSimctlCommandExecutor;
@class FBControlCoreLogger;
@class FBSimulatorBootConfiguration;
@class FBSimulatorConfiguration;
@class FBSimulatorSet;
@class FBTargetCommandCache;
@class SimDevice;

// Methods declared here are implemented via Swift extensions on FBSimulator.

/**
 An implementation of FBiOSTarget for iOS Simulators.
 */
// FBSimulator's async commands serialize their work onto FBFuture's internal
// queues, so instances are safe to pass across Swift concurrency domains.
NS_SWIFT_SENDABLE
@interface FBSimulator : NSObject <FBiOSTarget>

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

// FBSimulatorLifecycleCommandsProtocol- (nonnull FBFuture<NSNull *> *)disconnectWithTimeout:(NSTimeInterval)timeout logger:(nullable id<FBControlCoreLogger>)logger;
- (nonnull FBFuture *)connectToBridge;
- (nonnull FBFuture *)connectToFramebuffer;

// Lifecycle (legacy FBFuture entry points, ObjC-visible)
- (nonnull FBFuture<NSNull *> *)shutdown;
- (nonnull FBFuture<NSNull *> *)reboot;
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
 A command executor for simctl.
 Only used for video recording (`simctl io recordVideo`), which has no CoreSimulator API; all other
 operations spawn inside the simulator via CoreSimulator (see `-launchProcess:`).
 */
@property (nonnull, nonatomic, readonly, strong) FBAppleSimctlCommandExecutor *simctlExecutor;

/**
 The directory path of the expected location of the CoreSimulator logs directory.
 */
@property (nonnull, nonatomic, readonly, copy) NSString *coreSimulatorLogsDirectory;

#pragma mark - Should be marked private when converting to Swift

@property (nonnull, nonatomic, readonly, strong) FBTargetCommandCache *commandCache;

+ (nonnull instancetype)fromSimDevice:(nonnull SimDevice *)device configuration:(nullable FBSimulatorConfiguration *)configuration set:(nonnull FBSimulatorSet *)set;
- (nonnull instancetype)initWithDevice:(nonnull SimDevice *)device configuration:(nonnull FBSimulatorConfiguration *)configuration set:(nullable FBSimulatorSet *)set auxillaryDirectory:(nonnull NSString *)auxillaryDirectory logger:(nonnull id<FBControlCoreLogger>)logger reporter:(nonnull id<FBEventReporter>)reporter;
- (nonnull instancetype)initWithDevice:(nonnull id)device logger:(nonnull id<FBControlCoreLogger>)logger reporter:(nonnull id<FBEventReporter>)reporter;

@end

#pragma mark - Healthcheck Helpers

/**
 Convenience wrappers for interacting with CoreSimulator IPC surfaces
 without importing SimDevice or constructing Mach headers directly.
 */
@interface FBSimulator (FBHealthcheckHelpers)

/**
 Bootstrap-namespace lookup for a Mach port name in the simulator.
 Live XPC round-trip to the CoreSimulator daemon (SimDevice.lookup: is not cached).

 @param name The bootstrap port name to look up.
 @param error An error out parameter.
 @return The looked-up Mach port as an NSNumber, or nil on failure.
 */
- (nullable NSNumber *)lookupBootstrapPortNamed:(nonnull NSString *)name error:(NSError * _Nullable * _Nullable)error;

@end

// The accessibility translation dispatcher accessors
// (`createAccessibilityTranslationDispatcher(withTranslator:)` and
// `accessibilityTranslationDispatcher`) are now provided by a Swift extension on
// FBSimulator (see FBSimulatorAccessibilityCommands.swift).
