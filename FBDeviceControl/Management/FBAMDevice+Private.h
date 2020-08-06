/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <FBDeviceControl/FBAMDevice.h>
#import <FBDeviceControl/FBAMDefines.h>

NS_ASSUME_NONNULL_BEGIN

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
@property (nonatomic, assign, readwrite) AMDeviceRef amDeviceRef;

/**
 All of the Device Values available.
 */
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, id> *allValues;

/**
 The Context Manager for the Connection
 */
@property (nonatomic, strong, readonly) FBFutureContextManager<FBAMDevice *> *connectionContextManager;

/**
 The Service Manager.
 */
@property (nonatomic, strong, readonly) FBAMDeviceServiceManager *serviceManager;

/**
 The Queue on which work should be performed.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t workQueue;

#pragma mark Private Methods

/**
 The Designated Initializer

 @param allValues the values from the AMDevice.
 @param calls the calls to use.
 @param connectionReuseTimeout the time to wait before releasing a connection
 @param serviceReuseTimeout the time to wait before releasing a service
 @param workQueue the queue to perform work on.
 @param logger the logger to use.
 @return a new FBAMDevice instance.
 */
- (instancetype)initWithAllValues:(NSDictionary<NSString *, id> *)allValues calls:(AMDCalls)calls connectionReuseTimeout:(nullable NSNumber *)connectionReuseTimeout serviceReuseTimeout:(nullable NSNumber *)serviceReuseTimeout workQueue:(dispatch_queue_t)workQueue logger:(id<FBControlCoreLogger>)logger;

@end

NS_ASSUME_NONNULL_END
