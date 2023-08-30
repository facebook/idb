/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@class XCActivityRecord, XCTTestIdentifier;

@protocol XCTMessagingRole_ActivityReporting
- (id)_XCT_testCaseWithIdentifier:(XCTTestIdentifier *)arg1 didFinishActivity:(XCActivityRecord *)arg2;
- (id)_XCT_testCaseWithIdentifier:(XCTTestIdentifier *)arg1 willStartActivity:(XCActivityRecord *)arg2;
@end

