/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBFuture.h>
#import <FBControlCore/FBiOSTargetCommandForwarder.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Commands for simulating push notifications.
 */
@protocol FBNotificationCommands <NSObject, FBiOSTargetCommand>

/**
 Sends a notification

 @param bundleID of the target app
 @param jsonPayload notification data, see reference https://developer.apple.com/documentation/usernotifications/setting_up_a_remote_notification_server/generating_a_remote_notification
 @return a Future that resolves when successful.
 */
- (FBFuture<NSNull *> *)sendPushNotificationForBundleID:(NSString *)bundleID jsonPayload:(NSString *)jsonPayload;

@end

NS_ASSUME_NONNULL_END
