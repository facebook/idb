/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTestPrivate/XCTMessagingRole_ProcessMonitoring-Protocol.h>
#import <XCTestPrivate/XCTMessagingRole_TestExecution-Protocol.h>
#import <XCTestPrivate/XCTMessagingRole_TestExecution_Legacy-Protocol.h>
#import <XCTestPrivate/_XCTMessaging_VoidProtocol-Protocol.h>

@protocol XCTMessagingChannel_IDEToRunner <XCTMessagingRole_TestExecution, XCTMessagingRole_TestExecution_Legacy, XCTMessagingRole_ProcessMonitoring, _XCTMessaging_VoidProtocol>

@optional
- (void)__dummy_method_to_work_around_68987191;
@end
