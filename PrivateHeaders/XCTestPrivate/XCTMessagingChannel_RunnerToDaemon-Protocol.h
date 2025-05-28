/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@protocol XCTMessagingRole_ProtectedResourceAuthorization, XCTMessagingRole_CapabilityExchange, XCTMessagingRole_EventSynthesis, XCTMessagingRole_SiriAutomation, XCTMessagingRole_MemoryTesting, XCTMessagingRole_BundleRequesting, XCTMessagingRole_ForcePressureSupportQuerying, _XCTMessaging_VoidProtocol;

@protocol XCTMessagingChannel_RunnerToDaemon <XCTMessagingRole_ProtectedResourceAuthorization, XCTMessagingRole_CapabilityExchange, XCTMessagingRole_EventSynthesis, XCTMessagingRole_SiriAutomation, XCTMessagingRole_MemoryTesting, XCTMessagingRole_BundleRequesting, XCTMessagingRole_ForcePressureSupportQuerying, _XCTMessaging_VoidProtocol>

@optional
- (void)__dummy_method_to_work_around_68987191;
@end

