/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "ServiceDispatch.h"

#import "ContactsService.h"
#import "DnsService.h"
#import "HealthSettingsService.h"
#import "NotificationSettingsService.h"
#import "PhotoLibraryService.h"
#import "ProxyService.h"

int dispatchService(NSString *service, NSString *action, NSArray<NSString *> *arguments)
{
  if ([service isEqualToString:@"contacts"]) {
    return handleContactsAction(action);
  } else if ([service isEqualToString:@"dns"]) {
    return handleDnsAction(action, arguments);
  } else if ([service isEqualToString:@"photos"]) {
    return handlePhotoLibraryAction(action);
  } else if ([service isEqualToString:@"notifications"]) {
    NSString *bundleID = arguments.count > 0 ? arguments[0] : nil;
    return handleNotificationSettingsAction(action, bundleID);
  } else if ([service isEqualToString:@"health"]) {
    NSString *bundleID = arguments.count > 0 ? arguments[0] : nil;
    NSArray<NSString *> *typeIDs = arguments.count > 1
    ? [arguments subarrayWithRange:NSMakeRange(1, arguments.count - 1)]
    : @[];
    return handleHealthSettingsAction(action, bundleID, typeIDs);
  } else if ([service isEqualToString:@"proxy"]) {
    return handleProxyAction(action, arguments);
  } else {
    NSLog(@"Unknown service: %@", service);
    NSLog(@"Available services: contacts, dns, photos, notifications, health, proxy");
    return 1;
  }
}
