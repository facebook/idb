/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTestPrivate/XCTMessagingRole_ControlSessionInitiation-Protocol.h>
#import <XCTestPrivate/XCTMessagingRole_DiagnosticsCollection-Protocol.h>
#import <XCTestPrivate/XCTMessagingRole_RunnerSessionInitiation-Protocol.h>
#import <XCTestPrivate/XCTMessagingRole_UIRecordingControl-Protocol.h>
#import <XCTestPrivate/_XCTMessaging_VoidProtocol-Protocol.h>

@protocol XCTMessagingChannel_IDEToDaemon <XCTMessagingRole_RunnerSessionInitiation, XCTMessagingRole_ControlSessionInitiation, XCTMessagingRole_UIRecordingControl, XCTMessagingRole_DiagnosticsCollection, _XCTMessaging_VoidProtocol>

@optional
- (void)__dummy_method_to_work_around_68987191;
@end
