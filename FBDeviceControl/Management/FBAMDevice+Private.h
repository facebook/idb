/**
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

#pragma mark - Notifications

/**
 Notification for the Attachment of a Device.
 */
extern NSNotificationName const FBAMDeviceNotificationNameDeviceAttached;

/**
 Notification for the Detachment of a Device.
 */
extern NSNotificationName const FBAMDeviceNotificationNameDeviceDetached;

#pragma mark - AMDevice Class Private

@interface FBAMDevice () <FBFutureContextManagerDelegate>

#pragma mark Properties

/**
 The AMDevice Reference
 */
@property (nonatomic, assign, readwrite) AMDeviceRef amDevice;

/**
 The Context Manager for the Connection
 */
@property (nonatomic, strong, readonly) FBFutureContextManager<FBAMDevice *> *connectionContextManager;

/**
 The Service Manager.
 */
@property (nonatomic, strong, readonly) FBAMDeviceServiceManager *serviceManager;

/**
 The AMDCalls to be used.
 */
@property (nonatomic, assign, readonly) AMDCalls calls;

/**
 The Queue on which work should be performed.
 */
@property (nonatomic, strong, readonly) dispatch_queue_t workQueue;

/**
 The logger to log to.
 */
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

/**
 The default AMDevice calls.
 */
@property (nonatomic, assign, readonly, class) AMDCalls defaultCalls;

#pragma mark Private Methods

/**
 The Designated Initializer

 @param udid the UDID of the AMDevice.
 @param calls the calls to use.
 @param connectionReuseTimeout the time to wait before releasing a connection
 @param serviceReuseTimeout the time to wait before releasing a service
 @param workQueue the queue to perform work on.
 @param logger the logger to use.
 @return a new FBAMDevice instance.
 */
- (instancetype)initWithUDID:(NSString *)udid calls:(AMDCalls)calls connectionReuseTimeout:(nullable NSNumber *)connectionReuseTimeout serviceReuseTimeout:(nullable NSNumber *)serviceReuseTimeout workQueue:(dispatch_queue_t)workQueue logger:(id<FBControlCoreLogger>)logger;

/**
 Obtain the connection for a device.

 @param format the purpose of the connection
 @return a connection wrapped in an async context.
 */
- (FBFutureContext<FBAMDevice *> *)connectToDeviceWithPurpose:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

/**
 Starts test manager daemon service
 */
- (FBFutureContext<FBAMDServiceConnection *> *)startTestManagerService;

/**
 Starts a Service on the AMDevice.

 @param service the service name
 @return a Future wrapping the FBAFCConnection.
 */
- (FBFutureContext<FBAMDServiceConnection *> *)startService:(NSString *)service;

/**
 Starts an AFC Session on the Device.

 @return a Future wrapping the AFC connection.
 */
- (FBFutureContext<FBAMDServiceConnection *> *)startAFCService;

/**
 Starts house arrest for a given bundle id.

 @param bundleID the bundle id to use.
 @param afcCalls the AFC calls to inject
 @return a Future context wrapping the AFC Connection.
 */
- (FBFutureContext<FBAFCConnection *> *)houseArrestAFCConnectionForBundleID:(NSString *)bundleID afcCalls:(AFCCalls)afcCalls;

@end

NS_ASSUME_NONNULL_END
