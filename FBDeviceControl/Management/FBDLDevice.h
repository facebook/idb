/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBAMDevice;

/**
 An Object-Wrapper for a DLDevice Opaque Struct from DeviceLink.framework
 */
@interface FBDLDevice : NSObject

#pragma mark Initializers

/**
 The Designated Intitializer.
 Should only be called once per AMDevice.

 @param amDevice the FBAMDevice to wrap in a DLDevice.
 @return a Future, wrapping the device.
 */
+ (FBDLDevice *)deviceWithAMDevice:(FBAMDevice *)amDevice;

#pragma mark Properties

/**
 The UDID of the Device.
 */
@property (nonatomic, copy, readonly) NSString *udid;

#pragma mark Public Methods

/**
 Sends a message to a service.

 @param service the service name to connect to.
 @param request the request to send.
 @return a Future with a dictionary of the response.
 */
- (FBFuture<NSDictionary<NSString *, id> *> *)onService:(NSString *)service performRequest:(NSDictionary<NSString *, id> *)request;

/**
 Gets screenshot data.

 @return a Future with a dictionary of the response.
 */
- (FBFuture<NSData *> *)screenshotData;

@end

NS_ASSUME_NONNULL_END
