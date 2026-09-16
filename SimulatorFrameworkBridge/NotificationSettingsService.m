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
static const NSUInteger UNAuthorizationStatusNotDetermined = 0;
static const NSUInteger UNAuthorizationStatusAuthorized = 2;

@protocol NotificationSettingsGateway <NSObject>

- (BBSectionInfo *)sectionInfoForSectionID:(NSString *)sectionID;
- (void)setSectionInfo:(BBSectionInfo *)sectionInfo forSectionID:(NSString *)sectionID;
- (NSArray<NSString *> *)allSectionIDs;

@end

int handleNotificationSettingsActionWithGateway(
  NSString *action,
  NSString *bundleID,
  id<NotificationSettingsGateway> gateway
);

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
  // `null` rather than `false` on a runtime whose BBSectionInfo has no such property: the
  // flag is unknown there, not off. Both are reported because approve writes both, so
  // either one on its own cannot say whether the app will retain what it is shown.
  const char *showsInNotificationCenter = [sectionInfo respondsToSelector:@selector(showsInNotificationCenter)]
  ? ([sectionInfo showsInNotificationCenter] ? "true" : "false")
  : "null";
  const char *showsInLockScreen = [sectionInfo respondsToSelector:@selector(showsInLockScreen)]
  ? ([sectionInfo showsInLockScreen] ? "true" : "false")
  : "null";
  printf(
    "{\"bundleID\":\"%s\",\"found\":true,\"allowsNotifications\":%s,\"authorizationStatus\":%lu,\"showsInNotificationCenter\":%s,\"showsInLockScreen\":%s}\n",
    bundleID.UTF8String,
    [sectionInfo allowsNotifications] ? "true" : "false",
    (unsigned long)[sectionInfo authorizationStatus],
    showsInNotificationCenter,
    showsInLockScreen
  );
}

/**
 * Writes the effective visibility flags this runtime carries, and answers the ones it does not.
 *
 * The two are independent capabilities, probed separately for the same reason `check` reads them
 * separately: a runtime carrying one and not the other gets the one it carries, rather than
 * neither. Writing them together would leave a flag unset that the read side then reports as
 * `false` -- the "configured to retain nothing" reading that reporting the absent one as `null`
 * exists to avoid.
 */
static NSArray<NSString *> *setEffectiveVisibility(BBSectionInfo *sectionInfo, BOOL visible)
{
  NSMutableArray<NSString *> *absent = [NSMutableArray array];
  if ([sectionInfo respondsToSelector:@selector(setShowsInNotificationCenter:)]) {
    [sectionInfo setShowsInNotificationCenter:visible];
  } else {
    [absent addObject:@"showsInNotificationCenter"];
  }
  if ([sectionInfo respondsToSelector:@selector(setShowsInLockScreen:)]) {
    [sectionInfo setShowsInLockScreen:visible];
  } else {
    [absent addObject:@"showsInLockScreen"];
  }
  return absent;
}

int handleNotificationSettingsAction(NSString *action, NSString *bundleID)
{
  @try {
    BBSettingsGateway *gateway = loadGateway();
    if (!gateway) {
      return 1;
    }
    return handleNotificationSettingsActionWithGateway(action, bundleID, (id<NotificationSettingsGateway>)gateway);
  } @catch (NSException *exception) {
    NSLog(@"[NotificationSettings] Command raised: %@", exception);
    return 1;
  }
}

static int handleNotificationSettingsActionWithGatewayImpl(NSString *action,
                                                           NSString *bundleID,
                                                           id<NotificationSettingsGateway> gateway
)
{
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
    // The user-preference settings below are not the whole of approve. BulletinBoard decides
    // whether to RETAIN a delivered notification from the effective flags, so without those
    // an authorized app shows a banner and keeps nothing.
    [sectionInfo setAllowsNotifications:YES];
    [sectionInfo setAuthorizationStatus:UNAuthorizationStatusAuthorized];
    [sectionInfo setAlertType:1];
    [sectionInfo setLockScreenSetting:1];
    [sectionInfo setNotificationCenterSetting:1];
    // A runtime missing a flag still gets the authorization, and whatever flags it does have:
    // which of them exist is a property of that runtime, not of the request, and refusing would
    // take away the authorization approve used to grant rather than adding the retention it
    // could not. `check` reports an absent flag as `null`, so the state stays legible.
    NSArray<NSString *> *absent = setEffectiveVisibility(sectionInfo, YES);
    if (absent.count > 0) {
      NSLog(
        @"[NotificationSettings] This runtime's BBSectionInfo has no %@, so %@ is authorized but may not retain its notifications",
        [absent componentsJoinedByString:@" or "],
        bundleID
      );
    }
  } else if ([action isEqualToString:@"revoke"]) {
    if (!sectionInfo) {
      NSLog(@"[NotificationSettings] No section info for %@, nothing to revoke.", bundleID);
      return 0;
    }
    [sectionInfo setAllowsNotifications:NO];
    [sectionInfo setAuthorizationStatus:UNAuthorizationStatusNotDetermined];
    // The effective visibility flags are deliberately left alone. `revoke` resets an app to
    // never-having-asked, so the next authorization comes from the system rather than from
    // here -- and a system grant writes the authorization without rewriting these, so a clear
    // would outlive the revoke: the app comes back authorized with retention still off, which
    // is the state this service exists to prevent.
  } else {
    NSLog(@"[NotificationSettings] Unknown action: %@. Use approve, revoke, or check.", action);
    return 1;
  }

  [gateway setSectionInfo:sectionInfo forSectionID:bundleID];
  NSLog(@"[NotificationSettings] %@ notifications for %@", action, bundleID);
  return 0;
}

int handleNotificationSettingsActionWithGateway(NSString *action, NSString *bundleID, id<NotificationSettingsGateway> gateway)
{
  @try {
    return handleNotificationSettingsActionWithGatewayImpl(action, bundleID, gateway);
  } @catch (NSException *exception) {
    NSLog(@"[NotificationSettings] Command raised: %@", exception);
    return 1;
  }
}
