/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Synthetic header for BulletinBoard private API.
//
// BulletinBoard.framework is a private framework that manages
// notification settings via the bulletinboardd XPC daemon. Each app's
// notification preferences (authorization status, alert style, lock
// screen visibility) are stored as a BBSectionInfo keyed by bundle ID.
//
// Loaded at runtime via dlopen + NSClassFromString since the framework
// is not in the public iOS SDK.

#import <Foundation/Foundation.h>

@class BBSectionInfo;

/**
 * XPC client for the BulletinBoard daemon (bulletinboardd).
 * Provides read/write access to per-app notification settings.
 * Created via [[NSClassFromString(@"BBSettingsGateway") alloc] init]
 * after dlopen of BulletinBoard.framework.
 */
@interface BBSettingsGateway : NSObject

/**
 * Retrieves the notification settings for a given bundle ID.
 * Returns nil if the app has never requested notification authorization.
 */
- (BBSectionInfo *)sectionInfoForSectionID:(NSString *)sectionID;

/**
 * Writes notification settings for a given bundle ID. The daemon
 * persists the change and notifies the app on next launch.
 */
- (void)setSectionInfo:(BBSectionInfo *)sectionInfo forSectionID:(NSString *)sectionID;

/**
 * Returns all registered bundle IDs that have notification settings.
 */
- (NSArray<NSString *> *)allSectionIDs;

@end

/**
 * Represents notification settings for a single app (identified by
 * bundle ID). Properties delegate to an underlying BBSectionInfoSettings
 * object via the BBSectionInfoSettingsShortcuts category.
 */
@interface BBSectionInfo : NSObject

/**
 * Creates a default section info. sectionType 0 = application.
 * Use this to pre-approve notifications for an app before first launch.
 */
+ (instancetype)defaultSectionInfoForType:(NSUInteger)sectionType;

/** The bundle identifier this section applies to. */
@property (nonatomic, copy) NSString *sectionID;

/** Master toggle — whether the app is allowed to post notifications. */
@property (nonatomic) BOOL allowsNotifications;

/**
 * Maps to UNAuthorizationStatus values:
 *   0 = notDetermined, 1 = denied, 2 = authorized,
 *   3 = provisional, 4 = ephemeral.
 */
@property (nonatomic) NSUInteger authorizationStatus;

/** Alert presentation style: 0 = none, 1 = banner, 2 = alert. */
@property (nonatomic) NSUInteger alertType;

/** Whether notifications appear on the lock screen: 0 = off, 1 = on. */
@property (nonatomic) NSUInteger lockScreenSetting;

/** Whether notifications appear in Notification Center: 0 = off, 1 = on. */
@property (nonatomic) NSUInteger notificationCenterSetting;

@end
