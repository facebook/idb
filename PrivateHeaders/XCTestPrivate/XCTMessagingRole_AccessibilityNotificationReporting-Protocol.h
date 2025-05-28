/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class XCAccessibilityElement;

@protocol XCTMessagingRole_AccessibilityNotificationReporting
- (void)_XCT_receivedAccessibilityNotification:(int)arg1 fromElement:(XCAccessibilityElement *)arg2 payload:(NSData *)arg3;
- (void)_XCT_receivedAccessibilityNotification:(int)arg1 withPayload:(NSData *)arg2;
@end

