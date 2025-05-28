/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@protocol XCTestDriverInterface
- (id)_IDE_startExecutingTestPlanWithProtocolVersion:(NSNumber *)arg1;

// iOS 10.x specific
- (id)_IDE_processWithToken:(NSNumber *)arg1 exitedWithStatus:(NSNumber *)arg2;
- (id)_IDE_stopTrackingProcessWithToken:(NSNumber *)arg1;
- (id)_IDE_processWithBundleID:(NSString *)arg1 path:(NSString *)arg2 pid:(NSNumber *)arg3 crashedUnderSymbol:(NSString *)arg4;

@optional
- (id)_IDE_startExecutingTestPlanWhenReady;
@end
