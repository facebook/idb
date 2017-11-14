/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBApplicationCommands.h>
#import <FBControlCore/FBLogCommands.h>
#import <FBControlCore/FBArchitecture.h>
#import <FBControlCore/FBBitmapStreamingCommands.h>
#import <FBControlCore/FBDebugDescribeable.h>
#import <FBControlCore/FBJSONConversion.h>
#import <FBControlCore/FBVideoRecordingCommands.h>
#import <FBControlCore/FBXCTestCommands.h>

NS_ASSUME_NONNULL_BEGIN

@class FBDeviceType;
@class FBOSVersion;
@class FBProcessInfo;
@class FBiOSActionRouter;
@class FBiOSTargetDiagnostics;
@protocol FBDeviceOperator;
@protocol FBControlCoreLogger;

/**
 Uses the known values of SimDevice State, to construct an enumeration.
 These mirror the values from -[SimDeviceState state].
 */
typedef NS_ENUM(NSUInteger, FBSimulatorState) {
  FBSimulatorStateCreating = 0,
  FBSimulatorStateShutdown = 1,
  FBSimulatorStateBooting = 2,
  FBSimulatorStateBooted = 3,
  FBSimulatorStateShuttingDown = 4,
  FBSimulatorStateUnknown = 99,
};

/**
 Represents the kind of a target, device or simulator.
 */
typedef NS_OPTIONS(NSUInteger, FBiOSTargetType) {
  FBiOSTargetTypeNone = 0,
  FBiOSTargetTypeSimulator = 1 << 0,
  FBiOSTargetTypeDevice = 1 << 1,
  FBiOSTargetTypeAll = FBiOSTargetTypeSimulator | FBiOSTargetTypeDevice,
};

/**
 String Representations of Simulator State.
 */
typedef NSString *FBSimulatorStateString NS_STRING_ENUM;
extern FBSimulatorStateString const FBSimulatorStateStringCreating;
extern FBSimulatorStateString const FBSimulatorStateStringShutdown;
extern FBSimulatorStateString const FBSimulatorStateStringBooting;
extern FBSimulatorStateString const FBSimulatorStateStringBooted;
extern FBSimulatorStateString const FBSimulatorStateStringShuttingDown;
extern FBSimulatorStateString const FBSimulatorStateStringUnknown;

/**
 Common Properties of Devices & Simulators.
 */
@protocol FBiOSTarget <NSObject, FBJSONSerializable, FBDebugDescribeable, FBApplicationCommands, FBBitmapStreamingCommands, FBVideoRecordingCommands, FBXCTestCommands, FBLogCommands>

/**
 The Target's Logger.
 */
@property (nonatomic, strong, readonly, nullable) id<FBControlCoreLogger> logger;

/**
 The Action Classes supported by the reciever.
 */
@property (nonatomic, strong, readonly) NSArray<Class> *actionClasses;

/**
 The Unique Device Identifier of the iOS Target.
 */
@property (nonatomic, copy, readonly) NSString *udid;

/**
 The Name of the iOS Target. This is the name given by the user, such as "Ada's iPhone"
 */
@property (nonatomic, copy, readonly) NSString *name;

/**
 The Directory that FBSimulatorControl uses to store auxillary files.
 */
@property (nonatomic, copy, readonly) NSString *auxillaryDirectory;

/**
 The Diagnostics instance for the Target.
 */
@property (nonatomic, strong, readonly) FBiOSTargetDiagnostics *diagnostics;

/**
 The State of the iOS Target. Currently only applies to Simulators.
 */
@property (nonatomic, assign, readonly) FBSimulatorState state;

/**
 The Type of the iOS Target
 */
@property (nonatomic, assign, readonly) FBiOSTargetType targetType;

/**
 The Architecture of the iOS Target
 */
@property (nonatomic, copy, readonly) FBArchitecture architecture;

/**
 The Device Type of the Target.
 */
@property (nonatomic, copy, readonly) FBDeviceType *deviceType;

/**
 The OS Version of the Target.
 */
@property (nonatomic, copy, readonly) FBOSVersion *osVersion;

/**
 Process Information about the launchd process of the iOS Target. Currently only applies to Simulators.
 */
@property (nonatomic, copy, nullable, readonly) FBProcessInfo *launchdProcess;

/**
 Process Information about the Container Application of the iOS Target. Currently only applies to Simulators.
 */
@property (nonatomic, copy, nullable, readonly) FBProcessInfo *containerApplication;

/**
 Device operator used to control device. It provides API for XCTestBoostrap to interact with the device.
 */
@property (nonatomic, nullable, strong, readonly) id<FBDeviceOperator> deviceOperator;

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

/**
 The canonical string representation of the state enum.
 */
extern FBSimulatorStateString FBSimulatorStateStringFromState(FBSimulatorState state);

/**
 The canonical enum representation of the state string.
 */
extern FBSimulatorState FBSimulatorStateFromStateString(FBSimulatorStateString stateString);

/**
 The canonical string representations of the target type Option Set.
 */
NSArray<NSString *> *FBiOSTargetTypeStringsFromTargetType(FBiOSTargetType targetType);

/**
 The canonical enum representation of the state string.
 */
extern FBiOSTargetType FBiOSTargetTypeFromTargetTypeStrings(NSArray<NSString *> *targetTypeStrings);

/**
 A Default Comparison Function that can be called for different implementations of FBiOSTarget.
 */
extern NSComparisonResult FBiOSTargetComparison(id<FBiOSTarget> left, id<FBiOSTarget> right);

NS_ASSUME_NONNULL_END
