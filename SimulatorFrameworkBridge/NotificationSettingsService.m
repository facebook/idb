/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "NotificationSettingsService.h"

#import <dlfcn.h>

#import "BulletinBoardPrivate.h"

// UNAuthorizationStatus values
static const NSUInteger UNAuthorizationStatusDenied = 1;
static const NSUInteger UNAuthorizationStatusAuthorized = 2;

static BBSettingsGateway *loadGateway(void)
{
  if (!dlopen("/System/Library/PrivateFrameworks/BulletinBoard.framework/BulletinBoard", RTLD_NOW)) {
    NSLog(@"[NotificationSettings] Failed to load BulletinBoard.framework: %s", dlerror());
    return nil;
  }
  Class cls = NSClassFromString(@"BBSettingsGateway");
  if (!cls) {
    NSLog(@"[NotificationSettings] BBSettingsGateway class not found");
    return nil;
  }
  return [[cls alloc] init];
}

static void printSectionJSON(NSString *bundleID, BBSectionInfo *sectionInfo)
{
  if (!sectionInfo) {
    printf("{\"bundleID\":\"%s\",\"found\":false}\n", bundleID.UTF8String);
    return;
  }
  printf(
    "{\"bundleID\":\"%s\",\"found\":true,\"allowsNotifications\":%s,\"authorizationStatus\":%lu}\n",
    bundleID.UTF8String,
    [sectionInfo allowsNotifications] ? "true" : "false",
    (unsigned long)[sectionInfo authorizationStatus]
  );
}

int handleNotificationSettingsAction(NSString *action, NSString *bundleID)
{
  BBSettingsGateway *gateway = loadGateway();
  if (!gateway) {
    return 1;
  }

  if ([action isEqualToString:@"check"] || [action isEqualToString:@"list"]) {
    if (bundleID) {
      printSectionJSON(bundleID, [gateway sectionInfoForSectionID:bundleID]);
    } else {
      for (NSString *sectionID in [gateway allSectionIDs]) {
        printSectionJSON(sectionID, [gateway sectionInfoForSectionID:sectionID]);
      }
    }
    return 0;
  }

  if (!bundleID) {
    NSLog(@"[NotificationSettings] bundleID required for %@", action);
    return 1;
  }

  BBSectionInfo *sectionInfo = [gateway sectionInfoForSectionID:bundleID];

  if ([action isEqualToString:@"approve"]) {
    if (!sectionInfo) {
      // App is installed but hasn't launched or requested notification authorization yet.
      // Create a default section info so we can pre-approve before first launch.
      sectionInfo = [NSClassFromString(@"BBSectionInfo") defaultSectionInfoForType:0]; // 0 = application
      sectionInfo.sectionID = bundleID;
      NSLog(@"[NotificationSettings] Created new section info for %@", bundleID);
    }
    [sectionInfo setAllowsNotifications:YES];
    [sectionInfo setAuthorizationStatus:UNAuthorizationStatusAuthorized];
    [sectionInfo setAlertType:1];
    [sectionInfo setLockScreenSetting:1];
    [sectionInfo setNotificationCenterSetting:1];
  } else if ([action isEqualToString:@"revoke"]) {
    if (!sectionInfo) {
      NSLog(@"[NotificationSettings] No section info for %@, nothing to revoke.", bundleID);
      return 0;
    }
    [sectionInfo setAllowsNotifications:NO];
    [sectionInfo setAuthorizationStatus:UNAuthorizationStatusDenied];
  } else {
    NSLog(@"[NotificationSettings] Unknown action: %@. Use approve, revoke, or check.", action);
    return 1;
  }

  [gateway setSectionInfo:sectionInfo forSectionID:bundleID];
  NSLog(@"[NotificationSettings] %@ notifications for %@", action, bundleID);
  return 0;
}
