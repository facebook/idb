/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <FBDeviceControl/FBAMDefines.h>
#import <FBDeviceControl/FBAMDevice.h>

@class FBAFCConnection;
@class FBAMDServiceConnection;
@class FBAMDeviceServiceManager;

#pragma mark - AMDevice Class Private

@interface FBAMDevice () <FBFutureContextManagerDelegate>

#pragma mark Properties

/**
 The underyling AMDeviceRef.
 May be NULL.
 */
@property (nonatomic, readwrite, assign) AMDeviceRef _Nullable amDeviceRef;

/**
 All of the Device Values available.
 */
@property (nonnull, nonatomic, readwrite, copy) NSDictionary<NSString *, id> *allValues;

/**
 The Context Manager for the Connection
 */
@property (nonnull, nonatomic, readonly, strong) FBFutureContextManager<FBAMDevice *> *connectionContextManager;

/**
 The Service Manager.
 */
@property (nonnull, nonatomic, readonly, strong) FBAMDeviceServiceManager *serviceManager;

#pragma mark Private Methods

/**
 The Designated Initializer

 @param allValues the values from the AMDevice.
 @param calls the calls to use.
 @param connectionReuseTimeout the time to wait before releasing a connection
 @param serviceReuseTimeout the time to wait before releasing a service
 @param workQueue the queue on which work should be serialized.
 @param asyncQueue the queue on which asynchronous work can be performed sequentially.
 @param logger the logger to use.
 @return a new FBAMDevice instance.
 */
- (nonnull instancetype)initWithAllValues:(nonnull NSDictionary<NSString *, id> *)allValues calls:(AMDCalls)calls connectionReuseTimeout:(nullable NSNumber *)connectionReuseTimeout serviceReuseTimeout:(nullable NSNumber *)serviceReuseTimeout workQueue:(nonnull dispatch_queue_t)workQueue asyncQueue:(nonnull dispatch_queue_t)asyncQueue logger:(nonnull id<FBControlCoreLogger>)logger;

@end
