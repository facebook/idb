/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 * Modifies an app's notification permission via BulletinBoard, at runtime and without restarting
 * SpringBoard. `approve` sets authorized; `revoke` resets an existing decision to not determined;
 * `check`/`list` print the current state as JSON. Returns 0 on success.
 */
int handleNotificationSettingsAction(NSString *action, NSString *bundleID);
