/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "NotificationSettingsService.h"

#if __has_include(<SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>)
 #import <SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>
#else
 #import "SimulatorFrameworkBridgeSupport-Swift.h"
#endif

int handleNotificationSettingsActionWithGateway(NSString *action, NSString *bundleID, id gateway);

int handleNotificationSettingsAction(NSString *action, NSString *bundleID)
{
  return (int)[FBNotificationSettingsService handleNotificationSettingsAction:action bundleID:bundleID];
}

int handleNotificationSettingsActionWithGateway(NSString *action, NSString *bundleID, id gateway)
{
  return (int)[FBNotificationSettingsService handleNotificationSettingsActionWithGateway:action bundleID:bundleID gateway:gateway];
}
