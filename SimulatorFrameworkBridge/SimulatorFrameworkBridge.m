/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import "ContactsService.h"
#import "NotificationSettingsService.h"
#import "PhotoLibraryService.h"

int main(int argc, const char * argv[]) {
  @autoreleasepool {
    if (argc < 3) {
      NSLog(@"Usage: %s <service> <action> [args...]", argv[0]);
      NSLog(@"Services: contacts, photos, notifications");
      NSLog(@"Actions: clear, approve, revoke, check");
      return 1;
    }

    NSString *service = [NSString stringWithUTF8String:argv[1]];
    NSString *action = [NSString stringWithUTF8String:argv[2]];

    // Collect remaining args (argv[3..]) into an array for services that need them
    NSMutableArray<NSString *> *remainingArgs = [NSMutableArray array];
    for (int i = 3; i < argc; i++) {
      [remainingArgs addObject:[NSString stringWithUTF8String:argv[i]]];
    }

    if ([service isEqualToString:@"contacts"]) {
      return handleContactsAction(action);
    } else if ([service isEqualToString:@"photos"]) {
      return handlePhotoLibraryAction(action);
    } else if ([service isEqualToString:@"notifications"]) {
      NSString *bundleID = remainingArgs.count > 0 ? remainingArgs[0] : nil;
      return handleNotificationSettingsAction(action, bundleID);
    } else {
      NSLog(@"Unknown service: %@", service);
      NSLog(@"Available services: contacts, photos, notifications");
      return 1;
    }
    return 0;
  }
}
