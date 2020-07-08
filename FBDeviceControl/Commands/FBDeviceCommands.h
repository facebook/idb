/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBAMDefines.h>

NS_ASSUME_NONNULL_BEGIN

@class FBAMDevice;
@class FBAMDServiceConnection;
@class FBAFCConnection;

/**
 Defines Device-Specific commands, off which others are based.
 */
@protocol FBDeviceCommands <NSObject>

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
- (FBFutureContext<FBAFCConnection *> *)startAFCService;

/**
 Starts house arrest for a given bundle id.

 @param bundleID the bundle id to use.
 @param afcCalls the AFC calls to inject
 @return a Future context wrapping the AFC Connection.
 */
- (FBFutureContext<FBAFCConnection *> *)houseArrestAFCConnectionForBundleID:(NSString *)bundleID afcCalls:(AFCCalls)afcCalls;

#pragma mark Properties

/**
 The AMDevice Calls to use.
 */
@property (nonatomic, assign, readonly) AMDCalls calls;

/**
 The Device's 'Product Version'.
 */
@property (nonatomic, nullable, copy, readonly) NSString *productVersion;

/**
 The Device's 'Build Version'.
 */
@property (nonatomic, nullable, copy, readonly) NSString *buildVersion;

@end

NS_ASSUME_NONNULL_END
