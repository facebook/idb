/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetConstants.h>
#import <FBControlCore/FBApplicationCommands.h>
#import <FBControlCore/FBArchitecture.h>
#import <FBControlCore/FBVideoStreamCommands.h>
#import <FBControlCore/FBCrashLogCommands.h>
#import <FBControlCore/FBDebuggerCommands.h>
#import <FBControlCore/FBDapServerCommands.h>
#import <FBControlCore/FBInstrumentsCommands.h>
#import <FBControlCore/FBLogCommands.h>
#import <FBControlCore/FBScreenshotCommands.h>
#import <FBControlCore/FBVideoRecordingCommands.h>
#import <FBControlCore/FBXCTestCommands.h>
#import <FBControlCore/FBXCTraceRecordCommands.h>

NS_ASSUME_NONNULL_BEGIN

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
@property (nonatomic, copy, readonly) NSString *uniqueIdentifier;

/**
 The "Unique Device Identifier" of the iOS Target.
 This may be distinct from the uniqueIdentifier.
 */
@property (nonatomic, copy, readonly) NSString *udid;

/**
 The Name of the iOS Target. This is the name given by the user, such as "Ada's iPhone"
 */
@property (nonatomic, copy, readonly) NSString *name;

/**
 The Device Type of the Target.
 */
@property (nonatomic, copy, readonly) FBDeviceType *deviceType;

/**
 The Architecture of the iOS Target
 */
@property (nonatomic, copy, readonly) FBArchitecture architecture;

/**
 The OS Version of the Target.
 */
@property (nonatomic, copy, readonly) FBOSVersion *osVersion;

/**
 A dictionary containing per-target-type information that is unique to them.
 For example iOS Devices have additional metadata that is not present on Simulators.
 This dictionary must be JSON-Serializable.
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *extendedInformation;

/**
 The Type of the iOS Target
 */
@property (nonatomic, assign, readonly) FBiOSTargetType targetType;

/**
 The State of the iOS Target. Currently only applies to Simulators.
 */
@property (nonatomic, assign, readonly) FBiOSTargetState state;

@end

/**
 A protocol that defines an interactible and informational target.
 */
@protocol FBiOSTarget <NSObject, FBiOSTargetInfo, FBApplicationCommands, FBVideoStreamCommands, FBCrashLogCommands, FBLogCommands, FBScreenshotCommands, FBVideoRecordingCommands, FBXCTestCommands, FBXCTraceRecordCommands, FBInstrumentsCommands>

/**
 The Target's Logger.
 */
@property (nonatomic, strong, readonly, nullable) id<FBControlCoreLogger> logger;

/**
 The path to the custom (non-default) device set if applicable.
 */
@property (nonatomic, copy, nullable, readonly) NSString *customDeviceSetPath;

/**
 The directory that the target uses to store scratch files on the host.
 */
@property (nonatomic, strong, readonly) FBTemporaryDirectory *temporaryDirectory;

/**
 The directory that the target uses to store per-target files on the host.
 This should only be used for storing files that need to be preserved over the lifespan of the target.
 For example scratch or temporary files should *not* be stored here and -[FBiOSTarget temporaryDirectory] should be used instead..
 */
@property (nonatomic, copy, readonly) NSString *auxillaryDirectory;

/**
 The root of the "Runtime" where applicable
 */
@property (nonatomic, copy, readonly) NSString *runtimeRootDirectory;

/**
 The root of the "Runtime" where applicable
 */
@property (nonatomic, copy, readonly) NSString *platformRootDirectory;

/**
 The Screen Info for the Target.
 */
@property (nonatomic, copy, nullable, readonly) FBiOSTargetScreenInfo *screenInfo;

/**
 The Queue to serialize work on.
 This is a serial queue that should act as a lock for other tasks that will mutate the state of the target.
 Mutually Exclusive operations should use this queue.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t workQueue;

/**
 A queue for independent operations to execute on.
 Examples of these operations are transforming an immutable data structure.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t asyncQueue;

/**
 A Comparison Method for `sortedArrayUsingSelector:`

 @param target the target to compare to.
 @return a Comparison Result.
 */
- (NSComparisonResult)compare:(id<FBiOSTarget>)target;

/**
 If the target's bundle needs to be codesigned or not.

 @return if it needs to be signed or not.
 */
- (BOOL)requiresBundlesToBeSigned;

/**
  Env var replacements
 
  @return a dictionary with the replacements defined
 */
- (NSDictionary<NSString *, NSString *> *)replacementMapping;


@end

#if defined __cplusplus
extern "C" {
#endif
/**
 The canonical string representation of the state enum.
 */
extern FBiOSTargetStateString FBiOSTargetStateStringFromState(FBiOSTargetState state);

/**
 The canonical enum representation of the state string.
 */
extern FBiOSTargetState FBiOSTargetStateFromStateString(FBiOSTargetStateString stateString);

/**
 The canonical string representations of the FBiOSTargetType Enum.
 */
extern NSString *FBiOSTargetTypeStringFromTargetType(FBiOSTargetType targetType);

/**
 A Default Comparison Function that can be called for different implementations of FBiOSTarget.
 */
extern NSComparisonResult FBiOSTargetComparison(id<FBiOSTarget> left, id<FBiOSTarget> right);

/**
 Constructs a string description of the provided target.
 */
extern NSString *FBiOSTargetDescribe(id<FBiOSTargetInfo> target);

/**
 Constructs an NSPredicate matching the specified UDID.
 */
extern NSPredicate *FBiOSTargetPredicateForUDID(NSString *udid);

/**
 Constructs an NSPredicate matching the specified UDIDs.
 */
extern NSPredicate *FBiOSTargetPredicateForUDIDs(NSArray<NSString *> *udids);

/**
 Constructs a future that resolves when the target resolves to a provided state.
 */
extern FBFuture<NSNull *> *FBiOSTargetResolveState(id<FBiOSTarget> target, FBiOSTargetState state);

/**
 Constructs a future that resolves when the target leaves a provided state.
 */
extern FBFuture<NSNull *> *FBiOSTargetResolveLeavesState(id<FBiOSTarget> target, FBiOSTargetState state);

#if defined __cplusplus
};
#endif

NS_ASSUME_NONNULL_END
