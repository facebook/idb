/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "NotificationSettingsService.h"

#if __has_include(<SimulatorFrameworkBridgeRuntime/NotificationSettingsClient.h>)
 #import <SimulatorFrameworkBridgeRuntime/NotificationSettingsClient.h>
#else
 #import "Runtime/NotificationSettingsClient.h"
#endif

static const NSUInteger UNAuthorizationStatusNotDetermined = 0;
static const NSUInteger UNAuthorizationStatusAuthorized = 2;

int handleNotificationSettingsActionWithGateway(NSString *action, NSString *bundleID, id gateway);

static int handleNotificationSettingsActionWithClient(NSString *action, NSString *bundleID, FBNotificationSettingsClient *client);

static BOOL printSectionJSON(NSString *bundleID, FBNotificationSection *section)
{
  if (!section.isFound) {
    printf("{\"bundleID\":\"%s\",\"found\":false}\n", bundleID.UTF8String);
    return YES;
  }
  FBNotificationSectionValues *values = [section readValuesWithError:nil];
  if (!values) {
    return NO;
  }
  const char *showsInNotificationCenter = values.showsInNotificationCenter
  ? (values.showsInNotificationCenter.boolValue ? "true" : "false") : "null";
  const char *showsInLockScreen = values.showsInLockScreen
  ? (values.showsInLockScreen.boolValue ? "true" : "false") : "null";
  printf(
    "{\"bundleID\":\"%s\",\"found\":true,\"allowsNotifications\":%s,\"authorizationStatus\":%lu,\"showsInNotificationCenter\":%s,\"showsInLockScreen\":%s}\n",
    bundleID.UTF8String,
    values.allowsNotifications ? "true" : "false",
    (unsigned long)values.authorizationStatus,
    showsInNotificationCenter,
    showsInLockScreen
  );
  return YES;
}

int handleNotificationSettingsAction(NSString *action, NSString *bundleID)
{
  FBNotificationSettingsClient *client = [FBNotificationSettingsClient liveClient];
  if (!client) {
    return 1;
  }
  return handleNotificationSettingsActionWithClient(action, bundleID, client);
}

static int handleNotificationSettingsActionWithClient(NSString *action, NSString *bundleID, FBNotificationSettingsClient *client)
{
  if ([action isEqualToString:@"check"] || [action isEqualToString:@"list"]) {
    if (bundleID) {
      FBNotificationSection *section = [client sectionForIdentifier:bundleID error:nil];
      if (!section || !printSectionJSON(bundleID, section)) {
        return 1;
      }
    } else {
      NSArray<NSString *> *identifiers = [client allSectionIDsWithError:nil];
      if (!identifiers) {
        return 1;
      }
      for (NSString *sectionID in identifiers) {
        FBNotificationSection *section = [client sectionForIdentifier:sectionID error:nil];
        if (!section || !printSectionJSON(sectionID, section)) {
          return 1;
        }
      }
    }
    return 0;
  }

  if (!bundleID) {
    NSLog(@"[NotificationSettings] bundleID required for %@", action);
    return 1;
  }

  FBNotificationSection *section = [client sectionForIdentifier:bundleID error:nil];
  if (!section) {
    return 1;
  }

  if ([action isEqualToString:@"approve"]) {
    if (!section.isFound) {
      section = [client createSectionForIdentifier:bundleID error:nil];
      if (!section) {
        return 1;
      }
      NSLog(@"[NotificationSettings] Created new section info for %@", bundleID);
    }
    if (![section setAllowsNotifications:YES error:nil]
        || ![section setAuthorizationStatus:UNAuthorizationStatusAuthorized error:nil]
        || ![section setAlertType:1 error:nil]
        || ![section setLockScreenSetting:1 error:nil]
        || ![section setNotificationCenterSetting:1 error:nil]) {
      return 1;
    }
    NSArray<NSString *> *absent = [section setEffectiveVisibility:YES error:nil];
    if (!absent) {
      return 1;
    }
    if (absent.count > 0) {
      NSLog(
        @"[NotificationSettings] This runtime's BBSectionInfo has no %@, so %@ is authorized but may not retain its notifications",
        [absent componentsJoinedByString:@" or "],
        bundleID
      );
    }
  } else if ([action isEqualToString:@"revoke"]) {
    if (!section.isFound) {
      NSLog(@"[NotificationSettings] No section info for %@, nothing to revoke.", bundleID);
      return 0;
    }
    if (![section setAllowsNotifications:NO error:nil]
        || ![section setAuthorizationStatus:UNAuthorizationStatusNotDetermined error:nil]) {
      return 1;
    }
  } else {
    NSLog(@"[NotificationSettings] Unknown action: %@. Use approve, revoke, or check.", action);
    return 1;
  }

  if (![client writeSection:section forIdentifier:bundleID error:nil]) {
    return 1;
  }
  NSLog(@"[NotificationSettings] %@ notifications for %@", action, bundleID);
  return 0;
}

int handleNotificationSettingsActionWithGateway(NSString *action, NSString *bundleID, id gateway)
{
  return handleNotificationSettingsActionWithClient(action, bundleID, [[FBNotificationSettingsClient alloc] initWithGateway:gateway]);
}
