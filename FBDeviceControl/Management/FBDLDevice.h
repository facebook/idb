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

NS_ASSUME_NONNULL_BEGIN

/**
 An Object-Wrapper for a DLDevice Opaque Struct from DeviceLink.framework
 */
@interface FBDLDevice : NSObject

#pragma mark Initializers

/**
 Obtains a Device with the given identifier.

 @param udid the udid to obtain.
 @param timeout the timeout in seconds to wait for the device to appear.
 @return a Future, wrapping the device.
 */
+ (FBFuture<FBDLDevice *> *)deviceWithUDID:(NSString *)udid timeout:(NSTimeInterval)timeout;

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
