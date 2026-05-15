/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBDeviceControl/FBAMDefines.h>
#import <FBDeviceControl/FBDeviceManager.h>

@class FBAMDevice;

/**
 Class for obtaining FBAMDevice instances.
 */
@interface FBAMDeviceManager : FBDeviceManager <FBAMDevice *>

/**
 The Designated Initializer

 @param calls the AMDCalls to use.
 @param workQueue the queue on which work should be serialized.
 @param asyncQueue the queue on which asynchronous work can be performed sequentially.
 @param ecidFilter an ECID filter to apply.
 @param logger the logger to use.
 @return a new FBAMDeviceManager instance
 */
- (nonnull instancetype)initWithCalls:(AMDCalls)calls workQueue:(nonnull dispatch_queue_t)workQueue asyncQueue:(nonnull dispatch_queue_t)asyncQueue ecidFilter:(nonnull NSString *)ecidFilter logger:(nonnull id<FBControlCoreLogger>)logger;

/**
 Starts using the AMDeviceRef by doing the following:
 - Starts a Connection with the device
 - Performing and validating pairing.
 - Starts a session.

 @param device the device to use.
 @param calls the calls to use.
 @param logger the logger to use.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
+ (BOOL)startUsing:(AMDeviceRef _Nonnull)device calls:(AMDCalls)calls logger:(nonnull id<FBControlCoreLogger>)logger error:(NSError * _Nullable * _Nullable)error;

/**
 Stops using the AMDeviceRef connections.
 - Stops the session with the device.
 - Stops the connection with the device.

 @param device the device to use.
 @param calls the calls to use.
 @param logger the logger to use.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
+ (BOOL)stopUsing:(AMDeviceRef _Nonnull)device calls:(AMDCalls)calls logger:(nonnull id<FBControlCoreLogger>)logger error:(NSError * _Nullable * _Nullable)error;

@end
