/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTMessagingRole_UIAutomationEventReporting-Protocol.h>
#import <XCTest/_XCTMessaging_VoidProtocol-Protocol.h>

@protocol XCTMessagingChannel_DaemonRecorderToIDE <XCTMessagingRole_UIAutomationEventReporting, _XCTMessaging_VoidProtocol>

@optional
- (void)__dummy_method_to_work_around_68987191;
@end

