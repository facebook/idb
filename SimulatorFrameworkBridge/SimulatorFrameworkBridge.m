/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import "ContactsService.h"

int main(int argc, const char * argv[]) {
  @autoreleasepool {
    if (argc < 3) {
      NSLog(@"Usage: %s <service> <action>", argv[0]);
      NSLog(@"Services: contacts");
      NSLog(@"Actions: clear");
      return 1;
    }

    NSString *service = [NSString stringWithUTF8String:argv[1]];
    NSString *action = [NSString stringWithUTF8String:argv[2]];

    if ([service isEqualToString:@"contacts"]) {
      return handleContactsAction(action);
    } else {
      NSLog(@"Unknown service: %@", service);
      NSLog(@"Available services: contacts");
      return 1;
    }
    return 0;
  }
}
