/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 * Modifies notification permissions for apps via the BulletinBoard XPC service.
 * Uses BBSettingsGateway to update BBSectionInfo at runtime, avoiding
 * the need to restart SpringBoard.
 *
 * Usage:
 *   handleNotificationSettingsAction(@"approve", @"com.example.app")
 *   handleNotificationSettingsAction(@"revoke", @"com.example.app")
 *   handleNotificationSettingsAction(@"check", @"com.example.app")
 *
 * @param action "approve", "revoke", or "check"
 * @param bundleID the application bundle identifier
 * @return 0 on success, 1 on failure
 */
int handleNotificationSettingsAction(NSString *action, NSString *bundleID);
