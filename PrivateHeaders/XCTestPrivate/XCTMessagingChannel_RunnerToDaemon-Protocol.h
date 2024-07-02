/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTMessagingRole_BundleRequesting-Protocol.h>
#import <XCTest/XCTMessagingRole_CapabilityExchange-Protocol.h>
#import <XCTest/XCTMessagingRole_EventSynthesis-Protocol.h>
#import <XCTest/XCTMessagingRole_ForcePressureSupportQuerying-Protocol.h>
#import <XCTest/XCTMessagingRole_MemoryTesting-Protocol.h>
#import <XCTest/XCTMessagingRole_ProtectedResourceAuthorization-Protocol.h>
#import <XCTest/XCTMessagingRole_SiriAutomation-Protocol.h>
#import <XCTest/_XCTMessaging_VoidProtocol-Protocol.h>

@protocol XCTMessagingChannel_RunnerToDaemon <XCTMessagingRole_ProtectedResourceAuthorization, XCTMessagingRole_CapabilityExchange, XCTMessagingRole_EventSynthesis, XCTMessagingRole_SiriAutomation, XCTMessagingRole_MemoryTesting, XCTMessagingRole_BundleRequesting, XCTMessagingRole_ForcePressureSupportQuerying, _XCTMessaging_VoidProtocol>

@optional
- (void)__dummy_method_to_work_around_68987191;
@end

