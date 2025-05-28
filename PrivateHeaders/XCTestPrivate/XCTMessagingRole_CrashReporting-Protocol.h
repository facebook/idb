/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@protocol XCTMessagingRole_CrashReporting
- (id)_XCT_handleCrashReportData:(NSData *)arg1 fromFileWithName:(NSString *)arg2;
@end

