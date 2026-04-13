/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBAMDefines.h>
#import <FBDeviceControl/FBDeviceCommands.h>

/**
 An Object Wrapper around AMRestorableDevice
 */
@interface FBAMRestorableDevice : NSObject <FBiOSTargetInfo, FBDeviceProtocol>

#pragma mark - FBiOSTargetInfo Protocol Members
// Declared explicitly for Swift visibility since FBiOSTargetInfo is Swift-defined.
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
 The Designated Initializer.

 @param calls the calls to use.
 @param restorableDevice the AMRestorableDeviceRef
 @param allValues the cached device values.
 @param workQueue the queue on which work should be serialized.
 @param asyncQueue the queue on which asynchronous work can be performed sequentially.
 @param logger the logger to use.
 @return a new instance.
 */
- (nonnull instancetype)initWithCalls:(AMDCalls)calls restorableDevice:(AMRestorableDeviceRef _Nonnull)restorableDevice allValues:(nonnull NSDictionary<NSString *, id> *)allValues workQueue:(nonnull dispatch_queue_t)workQueue asyncQueue:(nonnull dispatch_queue_t)asyncQueue logger:(nonnull id<FBControlCoreLogger>)logger;

/**
 The Restorable Device instance.
 */
@property (nonatomic, readwrite, assign) AMRestorableDeviceRef _Nonnull restorableDevice;

/**
 Cached Device Values.
 */
@property (nonnull, nonatomic, readwrite, copy) NSDictionary<NSString *, id> *allValues;

/**
 The queue on which work should be serialized.
 */
@property (nonnull, nonatomic, readonly, strong) dispatch_queue_t workQueue;

/**
 The queue on which asynchronous work can be performed sequentially.
 */
@property (nonnull, nonatomic, readonly, strong) dispatch_queue_t asyncQueue;

/**
 Convert AMRestorableDeviceState to FBiOSTargetState.

 @param state the state integer.
 @return the FBiOSTargetState corresponding to the AMRestorableDeviceState
 */
+ (FBiOSTargetState)targetStateForDeviceState:(AMRestorableDeviceState)state;

@end
