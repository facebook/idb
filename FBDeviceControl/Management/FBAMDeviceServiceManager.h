/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import <FBDeviceControl/FBAFCConnection.h>

NS_ASSUME_NONNULL_BEGIN

@class FBAMDevice;

/**
 The Service Manager for an FBAMDevice instance.
 This allows for the pooling of services.
 */
@interface FBAMDeviceServiceManager : NSObject

#pragma mark Initializers

/**
 The Designated Initializer.

 @param device the device to manage services for.
 @param serviceTimeout the timeout to retain service for.
 @return a FBAMDeviceServiceManager instance.
 */
+ (instancetype)managerWithAMDevice:(FBAMDevice *)device serviceTimeout:(nullable NSNumber *)serviceTimeout;

#pragma mark Public Services

/**
 Obtain the Context Mannager

 @param bundleID the Bundle ID of the house_arrest service.
 @param afcCalls the calls to use.
 @return a FBFutureContextManager for the house_arrest service.
 */
- (FBFutureContextManager<FBAFCConnection *> *)houseArrestAFCConnectionForBundleID:(NSString *)bundleID afcCalls:(AFCCalls)afcCalls;

@end

NS_ASSUME_NONNULL_END
