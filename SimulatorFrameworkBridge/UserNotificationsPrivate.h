/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Synthetic header for UserNotifications private API.
//
// `UNUserNotificationCenter` is public, but its public entry point
// (`+currentNotificationCenter`) is scoped to the calling process. Reading another
// app's notifications needs the private initialiser below, which UserNotifications
// answers for any bundle that has registered notification settings.
//
// Declared here rather than cast at the call site, so the private surface this
// guest depends on stays visible in one place.

#import <UserNotifications/UserNotifications.h>

@interface UNUserNotificationCenter (FBPrivate)

/** A center scoped to `bundleIdentifier` rather than to the calling process. */
- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier;

@end
