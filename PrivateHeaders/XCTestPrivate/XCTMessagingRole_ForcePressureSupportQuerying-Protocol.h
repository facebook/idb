/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class XCSynthesizedEventRecord;

@protocol XCTMessagingRole_ForcePressureSupportQuerying
- (void)_XCT_synthesizeEvent:(XCSynthesizedEventRecord *)arg1 implicitConfirmationInterval:(double)arg2 completion:(void (^)(NSError *))arg3;
- (void)_XCT_postTelemetryData:(NSData *)arg1 reply:(void (^)(NSError *))arg2;
- (void)_XCT_requestPressureEventsSupported:(void (^)(_Bool, NSError *))arg1;
@end

