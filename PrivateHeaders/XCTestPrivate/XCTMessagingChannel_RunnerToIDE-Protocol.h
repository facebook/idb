/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import "XCTMessagingRole_ActivityReporting-Protocol.h"
#import "XCTMessagingRole_ActivityReporting_Legacy-Protocol.h"
#import "XCTMessagingRole_DebugLogging-Protocol.h"
#import "XCTMessagingRole_PerformanceMeasurementReporting-Protocol.h"
#import "XCTMessagingRole_PerformanceMeasurementReporting_Legacy-Protocol.h"
#import "XCTMessagingRole_SelfDiagnosisIssueReporting-Protocol.h"
#import "XCTMessagingRole_TestReporting-Protocol.h"
#import "XCTMessagingRole_TestReporting_Legacy-Protocol.h"
#import "XCTMessagingRole_UIAutomation-Protocol.h"
#import "_XCTMessaging_VoidProtocol-Protocol.h"

@protocol XCTMessagingChannel_RunnerToIDE <XCTMessagingRole_DebugLogging, XCTMessagingRole_TestReporting, XCTMessagingRole_TestReporting_Legacy, XCTMessagingRole_SelfDiagnosisIssueReporting, XCTMessagingRole_UIAutomation, XCTMessagingRole_ActivityReporting, XCTMessagingRole_ActivityReporting_Legacy, XCTMessagingRole_PerformanceMeasurementReporting, XCTMessagingRole_PerformanceMeasurementReporting_Legacy, _XCTMessaging_VoidProtocol>

@optional
- (void)__dummy_method_to_work_around_68987191;
@end

