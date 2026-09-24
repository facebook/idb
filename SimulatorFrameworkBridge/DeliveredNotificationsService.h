/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>

/**
 * Reads the notifications an app has had delivered to it, without touching the UI.
 *
 * The app under test does not have to be running, and nothing here launches,
 * foregrounds or otherwise disturbs it - which is what makes this usable from a
 * test that killed the app in order to exercise its push path.
 *
 * `delivered` prints one JSON object per delivered notification to stdout.
 * `clear-delivered` withdraws every notification the app is holding, printing nothing.
 * Returns 0 on success.
 */
int handleDeliveredNotificationsAction(NSString *action, NSString *bundleID);

/**
 * The part of `UNUserNotificationCenter` this service uses.
 *
 * Declared so the reading and formatting can be tested without a notification daemon; the
 * real center satisfies it as-is.
 */
@protocol FBDeliveredNotificationsCenter <NSObject>

- (void)getDeliveredNotificationsWithCompletionHandler:(void (^)(NSArray<UNNotification *> *notifications))completionHandler;

@end

/**
 * `handleDeliveredNotificationsAction` against a center the caller supplies.
 *
 * The seam a test drives: the entry point above builds a center scoped to the bundle under
 * test, and there is no daemon to answer one from a test process. Declared here rather than
 * beside the doubles so that the contract the implementation enforces is the one the test
 * surface states.
 */
int handleDeliveredNotificationsActionWithCenter(
  NSString *action,
  NSString *bundleID,
  id<FBDeliveredNotificationsCenter> center
);

/**
 * The part of `UNUserNotificationServiceConnection` the clear uses.
 *
 * Declared so the clear can be tested without a notification daemon; the real connection
 * satisfies it as-is.
 */
@protocol FBDeliveredNotificationsRemover <NSObject>

- (void)removeAllDeliveredNotificationsForBundleIdentifier:(NSString *)bundleIdentifier
                                         completionHandler:(void (^)(BOOL success))completionHandler;

@end

/**
 * The `clear-delivered` action against a remover the caller supplies, or none.
 *
 * The seam a test drives, as `handleDeliveredNotificationsActionWithCenter` is for reads. A nil
 * remover is the guest whose runtime has no connection to vend.
 */
int clearDeliveredNotificationsWithRemover(NSString *bundleID, id<FBDeliveredNotificationsRemover> remover);
