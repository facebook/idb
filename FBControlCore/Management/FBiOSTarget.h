/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBApplicationCommands.h>
#import <FBControlCore/FBArchitecture.h>
#import <FBControlCore/FBCrashLogCommands.h>
#import <FBControlCore/FBDapServerCommands.h>
#import <FBControlCore/FBDebuggerCommands.h>
#import <FBControlCore/FBInstrumentsCommands.h>
#import <FBControlCore/FBLifecycleCommands.h>
#import <FBControlCore/FBLogCommands.h>
#import <FBControlCore/FBScreenshotCommands.h>
#import <FBControlCore/FBVideoRecordingCommands.h>
#import <FBControlCore/FBVideoStreamCommands.h>
#import <FBControlCore/FBXCTestCommands.h>
#import <FBControlCore/FBXCTraceRecordCommands.h>
#import <FBControlCore/FBiOSTargetConstants.h>

@class FBDeviceType;
@class FBOSVersion;
@class FBProcessInfo;
@class FBTemporaryDirectory;
@class FBiOSTargetDiagnostics;
@class FBiOSTargetScreenInfo;
@protocol FBControlCoreLogger;

/**
 A protocol that defines an informational target.
 */
@protocol FBiOSTargetInfo <NSObject>

/**
 A Unique Identifier that describes this iOS Target.
 */
@property (nonnull, nonatomic, readonly, copy) NSString *uniqueIdentifier;

/**
 The "Unique Device Identifier" of the iOS Target.
 This may be distinct from the uniqueIdentifier.
 */
@property (nonnull, nonatomic, readonly, copy) NSString *udid;

/**
 The Name of the iOS Target. This is the name given by the user, such as "Ada's iPhone"
 */
@property (nonnull, nonatomic, readonly, copy) NSString *name;

/**
 The Device Type of the Target.
 */
@property (nonnull, nonatomic, readonly, copy) FBDeviceType *deviceType;

/**
 Available architecture of the iOS Target
 */
@property (nonnull, nonatomic, readonly, copy) NSArray<FBArchitecture> *architectures;

/**
 The OS Version of the Target.
 */
@property (nonnull, nonatomic, readonly, copy) FBOSVersion *osVersion;

/**
 A dictionary containing per-target-type information that is unique to them.
 For example iOS Devices have additional metadata that is not present on Simulators.
 This dictionary must be JSON-Serializable.
 */
@property (nonnull, nonatomic, readonly, copy) NSDictionary<NSString *, id> *extendedInformation;

/**
 The Type of the iOS Target
 */
@property (nonatomic, readonly, assign) FBiOSTargetType targetType;

/**
 The State of the iOS Target. Currently only applies to Simulators.
 */
@property (nonatomic, readonly, assign) FBiOSTargetState state;

@end

/**
 A protocol that defines an interactible and informational target.
 */
@protocol FBiOSTarget <NSObject, FBiOSTargetInfo, FBApplicationCommands, FBVideoStreamCommands, FBCrashLogCommands, FBLogCommands, FBScreenshotCommands, FBVideoRecordingCommands, FBXCTestCommands, FBXCTraceRecordCommandsProtocol, FBInstrumentsCommandsProtocol, FBLifecycleCommands>

/**
 The Target's Logger.
 */
@property (nullable, nonatomic, readonly, strong) id<FBControlCoreLogger> logger;

/**
 The path to the custom (non-default) device set if applicable.
 */
@property (nullable, nonatomic, readonly, copy) NSString *customDeviceSetPath;

/**
 The directory that the target uses to store scratch files on the host.
 */
@property (nonnull, nonatomic, readonly, strong) FBTemporaryDirectory *temporaryDirectory;

/**
 The directory that the target uses to store per-target files on the host.
 This should only be used for storing files that need to be preserved over the lifespan of the target.
 For example scratch or temporary files should *not* be stored here and -[FBiOSTarget temporaryDirectory] should be used instead..
 */
@property (nonnull, nonatomic, readonly, copy) NSString *auxillaryDirectory;

/**
 The root of the "Runtime" where applicable
 */
@property (nonnull, nonatomic, readonly, copy) NSString *runtimeRootDirectory;

/**
 The root of the "Platform" where applicable
 */
@property (nonnull, nonatomic, readonly, copy) NSString *platformRootDirectory;

/**
 The Screen Info for the Target.
 */
@property (nullable, nonatomic, readonly, copy) FBiOSTargetScreenInfo *screenInfo;

/**
 The Queue to serialize work on.
 This is a serial queue that should act as a lock for other tasks that will mutate the state of the target.
 Mutually Exclusive operations should use this queue.
 */
@property (nonnull, nonatomic, readonly, strong) dispatch_queue_t workQueue;

/**
 A queue for independent operations to execute on.
 Examples of these operations are transforming an immutable data structure.
 */
@property (nonnull, nonatomic, readonly, strong) dispatch_queue_t asyncQueue;

/**
 A Comparison Method for `sortedArrayUsingSelector:`

 @param target the target to compare to.
 @return a Comparison Result.
 */
- (NSComparisonResult)compare:(nonnull id<FBiOSTarget>)target;

/**
 If the target's bundle needs to be codesigned or not.

 @return if it needs to be signed or not.
 */
- (BOOL)requiresBundlesToBeSigned;

/**
  Env var replacements

  @return a dictionary with the replacements defined
 */
- (nonnull NSDictionary<NSString *, NSString *> *)replacementMapping;

/**
  Env var additions

  @return a dictionary with additional env vars to add
 */
- (nonnull NSDictionary<NSString *, NSString *> *)environmentAdditions;

@end

/**
 The canonical string representation of the state enum.
 */
FOUNDATION_EXTERN FBiOSTargetStateString _Nonnull FBiOSTargetStateStringFromState(FBiOSTargetState state);

/**
 The canonical enum representation of the state string.
 */
FOUNDATION_EXTERN FBiOSTargetState FBiOSTargetStateFromStateString(FBiOSTargetStateString _Nonnull stateString);

/**
 The canonical string representations of the FBiOSTargetType Enum.
 */
FOUNDATION_EXTERN NSString *_Nonnull FBiOSTargetTypeStringFromTargetType(FBiOSTargetType targetType);

/**
 A Default Comparison Function that can be called for different implementations of FBiOSTarget.
 */
FOUNDATION_EXTERN NSComparisonResult FBiOSTargetComparison(id<FBiOSTarget> _Nonnull left, id<FBiOSTarget> _Nonnull right);

/**
 Constructs a string description of the provided target.
 */
FOUNDATION_EXTERN NSString *_Nonnull FBiOSTargetDescribe(id<FBiOSTargetInfo> _Nonnull target);

/**
 Constructs an NSPredicate matching the specified UDID.
 */
FOUNDATION_EXTERN NSPredicate *_Nonnull FBiOSTargetPredicateForUDID(NSString * _Nonnull udid);

/**
 Constructs an NSPredicate matching the specified UDIDs.
 */
FOUNDATION_EXTERN NSPredicate *_Nonnull FBiOSTargetPredicateForUDIDs(NSArray<NSString *> * _Nonnull udids);

/**
 Constructs a future that resolves when the target resolves to a provided state.
 */
FOUNDATION_EXTERN FBFuture<NSNull *> *_Nonnull FBiOSTargetResolveState(id<FBiOSTarget> _Nonnull target, FBiOSTargetState state);

/**
 Constructs a future that resolves when the target leaves a provided state.
 */
FOUNDATION_EXTERN FBFuture<NSNull *> *_Nonnull FBiOSTargetResolveLeavesState(id<FBiOSTarget> _Nonnull target, FBiOSTargetState state);
