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

NS_ASSUME_NONNULL_BEGIN

/**
 An Object Wrapper around AMRestorableDevice
 */
@interface FBAMRestorableDevice : NSObject <FBiOSTargetInfo, FBDevice>

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
- (instancetype)initWithCalls:(AMDCalls)calls restorableDevice:(AMRestorableDeviceRef)restorableDevice allValues:(NSDictionary<NSString *, id> *)allValues workQueue:(dispatch_queue_t)workQueue asyncQueue:(dispatch_queue_t)asyncQueue logger:(id<FBControlCoreLogger>)logger;

/**
 The Restorable Device instance.
 */
@property (nonatomic, assign, readwrite) AMRestorableDeviceRef restorableDevice;

/**
 Cached Device Values.
 */
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, id> *allValues;

/**
 The queue on which work should be serialized.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t workQueue;

/**
 The queue on which asynchronous work can be performed sequentially.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t asyncQueue;

/**
 Convert AMRestorableDeviceState to FBiOSTargetState.

 @param state the state integer.
 @return the FBiOSTargetState corresponding to the AMRestorableDeviceState
 */
+ (FBiOSTargetState)targetStateForDeviceState:(AMRestorableDeviceState)state;

@end

NS_ASSUME_NONNULL_END
