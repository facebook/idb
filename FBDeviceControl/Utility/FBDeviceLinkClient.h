/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import <FBDeviceControl/FBServiceConnectionClient.h>

NS_ASSUME_NONNULL_BEGIN

@class FBServiceConnectionClient;

/**
 An implementation of a client for DeviceLink-based lockdown services.
 */
@interface FBDeviceLinkClient : NSObject

#pragma mark Initializers

/**
 Creates a plist client.

 @param client the client to use.
 @return a Future wrapping the FBPlistClient instance.
 */
+ (FBFuture<FBDeviceLinkClient *> *)deviceLinkClientWithServiceConnectionClient:(FBServiceConnectionClient *)client;

#pragma mark Public Methods

/**
 Sends a message request.

 @param message the message to send.
 @return a Future that resolves with the response.
 */
- (FBFuture<NSDictionary<id, id> *> *)processMessage:(id)message;

@end

NS_ASSUME_NONNULL_END
