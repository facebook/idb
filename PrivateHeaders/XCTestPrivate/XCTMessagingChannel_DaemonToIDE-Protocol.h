/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "XCTMessagingRole_CrashReporting-Protocol.h"
#import "XCTMessagingRole_DebugLogging-Protocol.h"
#import "XCTMessagingRole_SelfDiagnosisIssueReporting-Protocol.h"
#import "_XCTMessaging_VoidProtocol-Protocol.h"

@protocol XCTMessagingChannel_DaemonToIDE <XCTMessagingRole_DebugLogging, XCTMessagingRole_SelfDiagnosisIssueReporting, XCTMessagingRole_CrashReporting, _XCTMessaging_VoidProtocol>

@optional
- (void)__dummy_method_to_work_around_68987191;
@end

