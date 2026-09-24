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

/**
 * The client end of the connection to `usernotificationsd`, which every center shares.
 *
 * The daemon honours a request only for the bundle it identifies the calling process as, so a
 * guest can remove another app's notifications only while it is launched as that app.
 */
@interface UNUserNotificationServiceConnection : NSObject

+ (instancetype)sharedInstance;

/**
 * The daemon replies with `(BOOL success, NSError *error)`, but the second argument is not
 * always a valid object on this side, so the handler is declared without it.
 */
- (void)removeAllDeliveredNotificationsForBundleIdentifier:(NSString *)bundleIdentifier
                                         completionHandler:(void (^)(BOOL success))completionHandler;

@end
