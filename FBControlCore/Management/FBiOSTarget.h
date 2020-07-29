/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBApplicationCommands.h>
#import <FBControlCore/FBArchitecture.h>
#import <FBControlCore/FBBitmapStreamingCommands.h>
#import <FBControlCore/FBCrashLogCommands.h>
#import <FBControlCore/FBDebugDescribeable.h>
#import <FBControlCore/FBDebuggerCommands.h>
#import <FBControlCore/FBInstrumentsCommands.h>
#import <FBControlCore/FBJSONConversion.h>
#import <FBControlCore/FBLogCommands.h>
#import <FBControlCore/FBScreenshotCommands.h>
#import <FBControlCore/FBVideoRecordingCommands.h>
#import <FBControlCore/FBXCTestCommands.h>

NS_ASSUME_NONNULL_BEGIN

@class FBDeviceType;
@class FBOSVersion;
@class FBProcessInfo;
@class FBiOSTargetDiagnostics;
@class FBiOSTargetScreenInfo;
@protocol FBControlCoreLogger;

/**
 Uses the known values of SimDevice State, to construct an enumeration.
 These mirror the values from -[SimDeviceState state].
 */
typedef NS_ENUM(NSUInteger, FBiOSTargetState) {
  FBiOSTargetStateCreating = 0,
  FBiOSTargetStateShutdown = 1,
  FBiOSTargetStateBooting = 2,
  FBiOSTargetStateBooted = 3,
  FBiOSTargetStateShuttingDown = 4,
  FBiOSTargetStateDFU = 5,
  FBiOSTargetStateRecovery = 6,
  FBiOSTargetStateRestoreOS = 7,
  FBiOSTargetStateUnknown = 99,
};

/**
 Represents the kind of a target, device or simulator.
 */
typedef NS_OPTIONS(NSUInteger, FBiOSTargetType) {
  FBiOSTargetTypeNone = 0,
  FBiOSTargetTypeSimulator = 1 << 0,
  FBiOSTargetTypeDevice = 1 << 1,
  FBiOSTargetTypeLocalMac = 1 << 2,
  FBiOSTargetTypeAll = FBiOSTargetTypeSimulator | FBiOSTargetTypeDevice | FBiOSTargetTypeLocalMac,
};

/**
 String Representations of Simulator State.
 */
typedef NSString *FBiOSTargetStateString NS_STRING_ENUM;
extern FBiOSTargetStateString const FBiOSTargetStateStringCreating;
extern FBiOSTargetStateString const FBiOSTargetStateStringShutdown;
extern FBiOSTargetStateString const FBiOSTargetStateStringBooting;
extern FBiOSTargetStateString const FBiOSTargetStateStringBooted;
extern FBiOSTargetStateString const FBiOSTargetStateStringShuttingDown;
extern FBiOSTargetStateString const FBiOSTargetStateStringDFU;
extern FBiOSTargetStateString const FBiOSTargetStateStringRecovery;
extern FBiOSTargetStateString const FBiOSTargetStateStringRestoreOS;
extern FBiOSTargetStateString const FBiOSTargetStateStringUnknown;

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
@protocol FBiOSTarget <NSObject, FBiOSTargetInfo, FBJSONSerializable, FBDebugDescribeable, FBApplicationCommands, FBBitmapStreamingCommands, FBCrashLogCommands, FBLogCommands, FBScreenshotCommands, FBVideoRecordingCommands, FBXCTestCommands, FBInstrumentsCommands, FBDebuggerCommands>

/**
 The Target's Logger.
 */
@property (nonatomic, strong, readonly, nullable) id<FBControlCoreLogger> logger;

/**
 The Action Classes supported by the receiver.
 */
@property (nonatomic, strong, readonly) NSArray<Class> *actionClasses;


/**
 The Directory that the target uses to store per-target files on the host.
 */
@property (nonatomic, copy, readonly) NSString *auxillaryDirectory;

/**
 The Diagnostics instance for the Target.
 */
@property (nonatomic, strong, readonly) FBiOSTargetDiagnostics *diagnostics;

/**
 The Screen Info for the Target.
 */
@property (nonatomic, copy, nullable, readonly) FBiOSTargetScreenInfo *screenInfo;

/**
 Process Information about the launchd process of the iOS Target. Currently only applies to Simulators.
 */
@property (nonatomic, copy, nullable, readonly) FBProcessInfo *launchdProcess;

/**
 Process Information about the Container Application of the iOS Target. Currently only applies to Simulators.
 */
@property (nonatomic, copy, nullable, readonly) FBProcessInfo *containerApplication;

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
 The canonical string representations of the target type Option Set.
 */
extern NSArray<NSString *> *FBiOSTargetTypeStringsFromTargetType(FBiOSTargetType targetType);

/**
 The canonical enum representation of the state string.
 */
extern FBiOSTargetType FBiOSTargetTypeFromTargetTypeStrings(NSArray<NSString *> *targetTypeStrings);

/**
 A Default Comparison Function that can be called for different implementations of FBiOSTarget.
 */
extern NSComparisonResult FBiOSTargetComparison(id<FBiOSTarget> left, id<FBiOSTarget> right);

/**
 The default screenshot path for a target.

 @param storageDirectory the storage directory of the target to use.
 @return a file path.
 */
extern NSString *FBiOSTargetDefaultScreenshotPath(NSString *storageDirectory);

/**
 The default video path for a target.

 @param storageDirectory the storage directory of the target to use.
 @return a file path.
 */
extern NSString *FBiOSTargetDefaultVideoPath(NSString *storageDirectory);

#if defined __cplusplus
};
#endif

NS_ASSUME_NONNULL_END
