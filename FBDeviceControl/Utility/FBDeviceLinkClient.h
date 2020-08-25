/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBAMDServiceConnection;

/**
 An implementation of a client for DeviceLink-based lockdown services.
 All IO happens synchronously on a private background queue.
 Whilst there are ongoing operations upon this client, the Service Connection should not be used elsewhere.
 Once the constructor is called, this class should be the unique client of the Service Connection.
 */
@interface FBDeviceLinkClient : NSObject

#pragma mark Initializers

/**
 Creates a plist client.
 When the returned future has resolved successfully, the client is ready to use.

 @param connection the Service Connection to use.
 @return a Future wrapping the FBDeviceLinkClient instance.
 */
+ (FBFuture<FBDeviceLinkClient *> *)deviceLinkClientWithConnection:(FBAMDServiceConnection *)connection;

#pragma mark Public Methods

/**
 Sends a message request.

 @param message the message to send. Must be plist serializable.
 @return a Future that resolves with the response.
 */
- (FBFuture<NSDictionary<NSString *, id> *> *)processMessage:(id)message;

@end

NS_ASSUME_NONNULL_END
