/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class XCTTestIdentifier;

@protocol XCTMessagingRole_PerformanceMeasurementReporting
- (id)_XCT_testCaseWithIdentifier:(XCTTestIdentifier *)arg1 didMeasureMetric:(NSDictionary *)arg2 file:(NSString *)arg3 line:(NSNumber *)arg4;
@end

